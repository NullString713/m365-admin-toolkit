<#
.SYNOPSIS
Detects and enables Secure Boot on Lenovo endpoints.

.DESCRIPTION
This script checks the Lenovo BIOS Secure Boot setting by using Lenovo WMI classes.
If Secure Boot is disabled, the script attempts to enable it and save the BIOS setting.

This is designed as a public-safe Intune remediation example for Lenovo endpoints.
It does not include organization-specific values, tenant information, group IDs, or secrets.

The script can be used in two modes:

1. Detection mode:
   Use -DetectOnly to check whether Secure Boot is enabled.
   The script exits 0 when Secure Boot is enabled and exits 1 when remediation is needed.

2. Remediation mode:
   Run without -DetectOnly to attempt Secure Boot enablement.
   A restart is required before the change is fully applied.

.PARAMETER DetectOnly
Checks Secure Boot state only. Does not modify BIOS settings.

.PARAMETER PromptForRestart
Displays a best-effort restart message to signed-in users after Secure Boot is enabled.
This does not force a restart.

.PARAMETER LogPath
Path to the local log file.

.EXAMPLE
.\Enable-LenovoSecureBoot.ps1 -DetectOnly

Checks whether Secure Boot is enabled. Useful as an Intune remediation detection script.

.EXAMPLE
.\Enable-LenovoSecureBoot.ps1

Attempts to enable Secure Boot on supported Lenovo endpoints.

.EXAMPLE
.\Enable-LenovoSecureBoot.ps1 -PromptForRestart

Attempts to enable Secure Boot and displays a restart message to signed-in users.

.EXAMPLE
.\Enable-LenovoSecureBoot.ps1 -WhatIf

Shows what the script would do without making BIOS changes.

.NOTES
Author: Hali
Version: 1.0

Designed for:
- Lenovo endpoints
- Microsoft Intune remediation or script deployment
- Windows PowerShell running with administrative rights
- Environments where Secure Boot can be enabled through Lenovo WMI

Important:
- A restart is required after changing Secure Boot.
- This script does not force a restart.
- This script does not include BIOS supervisor password handling.
- If a BIOS supervisor password is configured, Lenovo WMI may return Access Denied unless password handling is added through an approved secure process.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [switch]$DetectOnly,

    [Parameter()]
    [switch]$PromptForRestart,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = "$env:ProgramData\HaliDev\Logs\Enable-LenovoSecureBoot.log"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLine = "[$Timestamp] [$Level] $Message"

    Write-Output $LogLine

    try {
        $LogDirectory = Split-Path -Path $LogPath -Parent

        if ($LogDirectory -and -not (Test-Path -Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }

        Add-Content -Path $LogPath -Value $LogLine
    }
    catch {
        Write-Output "[$Timestamp] [WARN] Could not write to log path '$LogPath'. $($_.Exception.Message)"
    }
}

function Test-IsAdministrator {
    $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($CurrentIdentity)

    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LenovoMethodReturnValue {
    param(
        [Parameter()]
        [object]$Result
    )

    if ($null -eq $Result) {
        return $null
    }

    if ($Result -is [string]) {
        return $Result
    }

    foreach ($PropertyName in @("return", "Return", "ReturnValue")) {
        $Property = $Result.PSObject.Properties[$PropertyName]

        if ($Property) {
            return [string]$Property.Value
        }
    }

    return ($Result | Out-String).Trim()
}

function Test-LenovoHardware {
    $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $Manufacturer = $ComputerSystem.Manufacturer

    Write-Log "Detected manufacturer: $Manufacturer"

    return ($Manufacturer -match "Lenovo")
}

function Test-LenovoWmiClasses {
    $RequiredClasses = @(
        "Lenovo_BiosSetting",
        "Lenovo_SetBiosSetting",
        "Lenovo_SaveBiosSettings"
    )

    foreach ($ClassName in $RequiredClasses) {
        try {
            Get-WmiObject -Namespace "root\wmi" -List -Class $ClassName -ErrorAction Stop | Out-Null
            Write-Log "Found Lenovo WMI class: $ClassName"
        }
        catch {
            throw "Required Lenovo WMI class '$ClassName' was not found in root\wmi."
        }
    }
}

function Get-LenovoSecureBootState {
    $SecureBootSetting = Get-WmiObject -Namespace "root\wmi" -Class Lenovo_BiosSetting -ErrorAction Stop |
        Where-Object {
            $_.CurrentSetting -like "SecureBoot,*"
        } |
        Select-Object -First 1

    if (-not $SecureBootSetting) {
        throw "Could not find the SecureBoot BIOS setting through Lenovo WMI."
    }

    $Parts = $SecureBootSetting.CurrentSetting -split ",", 2
    $CurrentValue = $Parts[1]

    [PSCustomObject]@{
        RawSetting = $SecureBootSetting.CurrentSetting
        Value      = $CurrentValue
        IsEnabled  = ($CurrentValue -in @("Enable", "Enabled"))
    }
}

function Enable-LenovoSecureBoot {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $SettingString = "SecureBoot,Enable"

    $SetBiosSetting = Get-WmiObject -Namespace "root\wmi" -Class Lenovo_SetBiosSetting -ErrorAction Stop
    $SaveBiosSettings = Get-WmiObject -Namespace "root\wmi" -Class Lenovo_SaveBiosSettings -ErrorAction Stop

    if ($PSCmdlet.ShouldProcess("Lenovo BIOS", "Set $SettingString")) {
        Write-Log "Attempting to set Lenovo BIOS setting: $SettingString"

        $SetResult = $SetBiosSetting.SetBiosSetting($SettingString)
        $SetReturnValue = Get-LenovoMethodReturnValue -Result $SetResult

        if ($SetReturnValue) {
            Write-Log "SetBiosSetting returned: $SetReturnValue"
        }

        if ($SetReturnValue -and $SetReturnValue -ne "Success") {
            throw "SetBiosSetting did not return Success. Returned: $SetReturnValue"
        }

        Write-Log "Attempting to save Lenovo BIOS settings."

        $SaveResult = $SaveBiosSettings.SaveBiosSettings()
        $SaveReturnValue = Get-LenovoMethodReturnValue -Result $SaveResult

        if ($SaveReturnValue) {
            Write-Log "SaveBiosSettings returned: $SaveReturnValue"
        }

        if ($SaveReturnValue -and $SaveReturnValue -ne "Success") {
            throw "SaveBiosSettings did not return Success. Returned: $SaveReturnValue"
        }
    }
}

function Show-RestartMessage {
    $Message = "Secure Boot was enabled for compliance. Please save your work and restart this computer."

    try {
        Write-Log "Attempting to display restart message to signed-in users."
        & "$env:SystemRoot\System32\msg.exe" * /TIME:600 $Message | Out-Null
    }
    catch {
        Write-Log "Could not display restart message. $($_.Exception.Message)" "WARN"
    }
}

try {
    Write-Log "Starting Lenovo Secure Boot check."

    if (-not (Test-IsAdministrator)) {
        throw "This script must run with administrative rights."
    }

    if (-not (Test-LenovoHardware)) {
        Write-Log "This device is not Lenovo hardware. No action required."
        exit 0
    }

    Test-LenovoWmiClasses

    $SecureBootState = Get-LenovoSecureBootState
    Write-Log "Current Lenovo Secure Boot setting: $($SecureBootState.RawSetting)"

    if ($SecureBootState.IsEnabled) {
        Write-Log "Secure Boot is already enabled. No action required."
        exit 0
    }

    if ($DetectOnly) {
        Write-Log "Secure Boot is not enabled. Remediation is required." "WARN"
        exit 1
    }

    Enable-LenovoSecureBoot

    Write-Log "Secure Boot enablement command completed. A restart is required for the change to fully apply."

    if ($PromptForRestart) {
        Show-RestartMessage
    }

    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    exit 1
}
