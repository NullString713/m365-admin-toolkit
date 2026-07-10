<#
.SYNOPSIS
Collects Windows Autopilot hardware hash data and exports import-ready CSV files.

.DESCRIPTION
This script collects the local device serial number and Windows Autopilot hardware hash,
then exports the data to an individual device CSV and a combined CSV that can be imported
into Windows Autopilot.

It is designed for USB-based or technician-driven collection workflows where multiple
devices are processed one at a time and their CSV files are collected into a shared folder.

The script supports an optional Autopilot group tag. The group tag can be provided as a
parameter or read from a Group-Tag.txt file in the script folder.

This public version is intentionally generic:
- No tenant IDs
- No company-specific paths
- No internal group tags
- No user names
- No upload to Intune
- No secrets

.PARAMETER GroupTag
Optional Autopilot group tag to include in the exported CSV.

.PARAMETER GroupTagFile
Optional path to a text file containing the Autopilot group tag. Defaults to Group-Tag.txt
in the script folder.

.PARAMETER OutputRoot
Root folder where CSV, combined CSV, and log files are written. Defaults to the script folder.

.PARAMETER CombineOnly
Rebuilds the combined CSV from existing individual CSV files without collecting hardware hash
from the current device.

.EXAMPLE
.\Export-AutopilotHardwareHash.ps1

Collects the local device hardware hash. If Group-Tag.txt exists in the script folder, the
first non-empty line is used as the group tag.

.EXAMPLE
.\Export-AutopilotHardwareHash.ps1 -GroupTag "KIOSK-WAREHOUSE"

Collects the local device hardware hash and exports it with the group tag KIOSK-WAREHOUSE.

.EXAMPLE
.\Export-AutopilotHardwareHash.ps1 -OutputRoot "E:\Autopilot"

Collects the local device hardware hash and writes output under E:\Autopilot.

.EXAMPLE
.\Export-AutopilotHardwareHash.ps1 -CombineOnly

Rebuilds the combined CSV from existing individual CSV files.

.NOTES
Author: Hali
Version: 1.0

Designed for:
- Windows Autopilot device registration
- USB-based hardware hash collection
- Technician workflows
- Autopilot group tag assignment
- Public-safe Intune portfolio examples

Requires:
- Administrative rights
- Access to the MDM_DevDetail_Ext01 CIM class
- Windows device capable of returning Autopilot hardware hash data
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GroupTag,

    [Parameter()]
    [string]$GroupTagFile,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot,

    [Parameter()]
    [switch]$CombineOnly
)

$ErrorActionPreference = "Stop"

function Get-DefaultScriptRoot {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    return (Get-Location).Path
}

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
        if (-not (Test-Path -Path $script:LogFolder)) {
            New-Item -Path $script:LogFolder -ItemType Directory -Force | Out-Null
        }

        Add-Content -Path $script:LogPath -Value $LogLine -Encoding UTF8
    }
    catch {
        Write-Output "[$Timestamp] [WARN] Could not write to log file. $($_.Exception.Message)"
    }
}

function Test-IsAdministrator {
    $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($CurrentIdentity)

    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-DirectoryIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-SafeFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $InvalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()

    foreach ($Character in $InvalidCharacters) {
        $Value = $Value.Replace($Character, "-")
    }

    return $Value
}

function Get-AutopilotGroupTag {
    param(
        [Parameter()]
        [string]$GroupTag,

        [Parameter()]
        [string]$GroupTagFile
    )

    if ($GroupTag) {
        return $GroupTag.Trim()
    }

    if ($GroupTagFile -and (Test-Path -Path $GroupTagFile)) {
        $FileValue = Get-Content -Path $GroupTagFile -ErrorAction Stop |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            } |
            Select-Object -First 1

        if ($FileValue) {
            return $FileValue.Trim()
        }
    }

    return $null
}

function Get-AutopilotHardwareHash {
    Write-Log "Reading BIOS serial number."
    $SerialNumber = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber

    if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
        throw "Could not read BIOS serial number."
    }

    Write-Log "Reading Autopilot hardware hash from MDM_DevDetail_Ext01."

    $DeviceDetail = Get-CimInstance `
        -Namespace "root/cimv2/mdm/dmmap" `
        -ClassName "MDM_DevDetail_Ext01" `
        -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" `
        -ErrorAction Stop

    if (-not $DeviceDetail -or [string]::IsNullOrWhiteSpace($DeviceDetail.DeviceHardwareData)) {
        throw "Unable to retrieve Autopilot hardware hash from this device."
    }

    [PSCustomObject]@{
        SerialNumber = $SerialNumber.Trim()
        ProductId    = $null
        HardwareHash = $DeviceDetail.DeviceHardwareData
    }
}

function New-AutopilotCsvObject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SerialNumber,

        [Parameter()]
        [string]$ProductId,

        [Parameter(Mandatory = $true)]
        [string]$HardwareHash,

        [Parameter()]
        [string]$GroupTag
    )

    $Properties = [ordered]@{
        "Device Serial Number" = $SerialNumber
        "Windows Product ID"   = $ProductId
        "Hardware Hash"        = $HardwareHash
    }

    if ($GroupTag) {
        $Properties["Group Tag"] = $GroupTag
    }

    [PSCustomObject]$Properties
}

function Export-AutopilotCsv {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $CsvContent = $InputObject |
        ConvertTo-Csv -NoTypeInformation |
        ForEach-Object {
            $_ -replace '"', ''
        }

    Set-Content -Path $Path -Value $CsvContent -Encoding UTF8
}

function Update-CombinedAutopilotCsv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IndividualCsvFolder,

        [Parameter(Mandatory = $true)]
        [string]$CombinedCsvPath
    )

    $CsvFiles = Get-ChildItem -Path $IndividualCsvFolder -Filter "*.csv" -File -ErrorAction SilentlyContinue |
        Sort-Object Name

    if (-not $CsvFiles -or $CsvFiles.Count -eq 0) {
        Write-Log "No individual CSV files found to combine." "WARN"
        return
    }

    Write-Log "Combining $($CsvFiles.Count) individual CSV file(s)."

    $CombinedRows = foreach ($CsvFile in $CsvFiles) {
        Import-Csv -Path $CsvFile.FullName
    }

    if (-not $CombinedRows) {
        Write-Log "No CSV rows found to combine." "WARN"
        return
    }

    Export-AutopilotCsv -InputObject $CombinedRows -Path $CombinedCsvPath
    Write-Log "Combined CSV updated: $CombinedCsvPath"
}

try {
    $ScriptRoot = Get-DefaultScriptRoot

    if (-not $OutputRoot) {
        $OutputRoot = $ScriptRoot
    }

    if (-not $GroupTagFile) {
        $GroupTagFile = Join-Path -Path $ScriptRoot -ChildPath "Group-Tag.txt"
    }

    $CsvFolder = Join-Path -Path $OutputRoot -ChildPath "csv"
    $CombinedFolder = Join-Path -Path $OutputRoot -ChildPath "combined"
    $script:LogFolder = Join-Path -Path $OutputRoot -ChildPath "logs"
    $script:LogPath = Join-Path -Path $script:LogFolder -ChildPath "Export-AutopilotHardwareHash.log"
    $CombinedCsvPath = Join-Path -Path $CombinedFolder -ChildPath "combinedlisting.csv"

    New-DirectoryIfMissing -Path $CsvFolder
    New-DirectoryIfMissing -Path $CombinedFolder
    New-DirectoryIfMissing -Path $script:LogFolder

    Write-Log "Starting Autopilot hardware hash export."
    Write-Log "Output root: $OutputRoot"

    if (-not (Test-IsAdministrator)) {
        throw "This script must run with administrative rights."
    }

    if ($CombineOnly) {
        Write-Log "CombineOnly specified. Skipping hardware hash collection."
        Update-CombinedAutopilotCsv -IndividualCsvFolder $CsvFolder -CombinedCsvPath $CombinedCsvPath
        exit 0
    }

    $ResolvedGroupTag = Get-AutopilotGroupTag -GroupTag $GroupTag -GroupTagFile $GroupTagFile

    if ($ResolvedGroupTag) {
        Write-Log "Using Autopilot group tag: $ResolvedGroupTag"
    }
    else {
        Write-Log "No Autopilot group tag provided. CSV will not include Group Tag column." "WARN"
    }

    $DeviceInfo = Get-AutopilotHardwareHash

    $CsvObject = New-AutopilotCsvObject `
        -SerialNumber $DeviceInfo.SerialNumber `
        -ProductId $DeviceInfo.ProductId `
        -HardwareHash $DeviceInfo.HardwareHash `
        -GroupTag $ResolvedGroupTag

    $SafeComputerName = Get-SafeFileName -Value $env:COMPUTERNAME
    $SafeSerialNumber = Get-SafeFileName -Value $DeviceInfo.SerialNumber
    $IndividualCsvPath = Join-Path -Path $CsvFolder -ChildPath "$SafeComputerName-$SafeSerialNumber.csv"

    Export-AutopilotCsv -InputObject $CsvObject -Path $IndividualCsvPath
    Write-Log "Individual CSV exported: $IndividualCsvPath"

    Update-CombinedAutopilotCsv -IndividualCsvFolder $CsvFolder -CombinedCsvPath $CombinedCsvPath

    Write-Log "Autopilot hardware hash export completed."
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    exit 1
}
