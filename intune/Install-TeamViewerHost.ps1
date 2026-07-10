<#
.SYNOPSIS
Downloads and installs TeamViewer Host with optional assignment configuration.

.DESCRIPTION
This script downloads a TeamViewer Host deployment package, extracts it when needed,
locates the TeamViewer Host MSI, and installs it silently with optional deployment
configuration parameters.

This is designed as a public-safe Intune/software deployment example. It does not
include organization-specific download URLs, API tokens, assignment IDs, custom
configuration IDs, group IDs, policy IDs, or secrets.

The script supports common deployment patterns:

- Download latest TeamViewer Host package from a supplied URL
- Extract a ZIP package when the download is compressed
- Locate TeamViewer_Host.msi automatically
- Install TeamViewer Host silently through msiexec
- Pass optional TeamViewer deployment values such as CUSTOMCONFIGID, APITOKEN,
  ASSIGNMENTID, and ASSIGNMENTOPTIONS
- Log actions to ProgramData
- Support -WhatIf through PowerShell ShouldProcess

.PARAMETER DownloadUrl
The TeamViewer Host download URL. Do not publish private/vendor-provided deployment URLs
if they are unique to your organization.

.PARAMETER CustomConfigId
Optional TeamViewer custom configuration ID.

.PARAMETER ApiToken
Optional TeamViewer API token used by some deployment methods.
Avoid hardcoding this value in production scripts. Use your MDM, automation platform,
or secret-management process.

.PARAMETER AssignmentId
Optional TeamViewer assignment ID used by some deployment methods.

.PARAMETER AssignmentOptions
Optional TeamViewer assignment options string, such as:
--grant-easy-access --reassign

.PARAMETER WorkPath
Temporary working directory used for download and extraction.

.PARAMETER LogPath
Path to the local log file.

.PARAMETER KeepInstallerFiles
Keeps downloaded and extracted installer files after installation.

.EXAMPLE
.\Install-TeamViewerHost.ps1 `
  -DownloadUrl "https://example.com/TeamViewer_MSI32.zip" `
  -CustomConfigId "REDACTED_CUSTOM_CONFIG_ID" `
  -ApiToken "REDACTED_API_TOKEN" `
  -AssignmentOptions "--grant-easy-access --reassign"

Downloads, extracts, and installs TeamViewer Host with a custom configuration ID,
API token, and assignment options.

.EXAMPLE
.\Install-TeamViewerHost.ps1 `
  -DownloadUrl "https://example.com/TeamViewer_MSI32.zip" `
  -CustomConfigId "REDACTED_CUSTOM_CONFIG_ID" `
  -AssignmentId "REDACTED_ASSIGNMENT_ID"

Downloads, extracts, and installs TeamViewer Host with a custom configuration ID
and assignment ID.

.EXAMPLE
.\Install-TeamViewerHost.ps1 `
  -DownloadUrl "https://example.com/TeamViewer_MSI32.zip" `
  -WhatIf

Shows the actions the script would take without downloading, extracting, installing,
or deleting installer files.

.NOTES
Author: Hali
Version: 1.0

Designed for:
- Microsoft Intune script deployment
- Endpoint software deployment examples
- TeamViewer Host MSI deployment
- Silent install workflows
- Public-safe portfolio/repo demonstration

Security:
- Do not hardcode real API tokens, assignment IDs, custom configuration IDs, group IDs,
  policy IDs, private download URLs, or internal paths in public repositories.
- Store sensitive values through Intune, Azure Automation, your RMM, or an approved
  secret-management process.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DownloadUrl,

    [Parameter()]
    [string]$CustomConfigId,

    [Parameter()]
    [string]$ApiToken,

    [Parameter()]
    [string]$AssignmentId,

    [Parameter()]
    [string]$AssignmentOptions = "--grant-easy-access --reassign",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WorkPath = "$env:ProgramData\HaliDev\Installers\TeamViewerHost",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = "$env:ProgramData\HaliDev\Logs\Install-TeamViewerHost.log",

    [Parameter()]
    [switch]$KeepInstallerFiles
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

function New-DirectoryIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, "Create directory")) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
    }
}

function Get-TeamViewerInstallState {
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $InstalledApp = foreach ($RegistryPath in $RegistryPaths) {
        Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -like "TeamViewer Host*"
            } |
            Select-Object -First 1
    }

    if ($InstalledApp) {
        return [PSCustomObject]@{
            IsInstalled    = $true
            DisplayName    = $InstalledApp.DisplayName
            DisplayVersion = $InstalledApp.DisplayVersion
        }
    }

    return [PSCustomObject]@{
        IsInstalled    = $false
        DisplayName    = $null
        DisplayVersion = $null
    }
}

function Get-FileNameFromUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    try {
        $Uri = [System.Uri]$Url
        $FileName = [System.IO.Path]::GetFileName($Uri.LocalPath)

        if ($FileName) {
            return $FileName
        }
    }
    catch {
        Write-Log "Could not parse filename from URL. Falling back to TeamViewerHostPackage.zip." "WARN"
    }

    return "TeamViewerHostPackage.zip"
}

function Save-RemoteFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUrl,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if ($PSCmdlet.ShouldProcess($SourceUrl, "Download to $DestinationPath")) {
        Write-Log "Downloading TeamViewer Host package."
        Write-Log "Destination: $DestinationPath"

        try {
            Start-BitsTransfer -Source $SourceUrl -Destination $DestinationPath -ErrorAction Stop
        }
        catch {
            Write-Log "BITS download failed. Falling back to Invoke-WebRequest. $($_.Exception.Message)" "WARN"
            Invoke-WebRequest -Uri $SourceUrl -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
        }
    }
}

function Expand-TeamViewerPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $Extension = [System.IO.Path]::GetExtension($PackagePath)

    if ($Extension -ieq ".zip") {
        if ($PSCmdlet.ShouldProcess($PackagePath, "Extract package to $DestinationPath")) {
            Write-Log "Extracting package."
            Expand-Archive -Path $PackagePath -DestinationPath $DestinationPath -Force
        }
    }
    else {
        Write-Log "Package is not a ZIP file. Extraction skipped."
    }
}

function Find-TeamViewerHostMsi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchPath
    )

    $PreferredNames = @(
        "TeamViewer_Host.msi",
        "TeamViewer_host.msi"
    )

    foreach ($PreferredName in $PreferredNames) {
        $Match = Get-ChildItem -Path $SearchPath -Recurse -Filter $PreferredName -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($Match) {
            return $Match.FullName
        }
    }

    $FallbackMatch = Get-ChildItem -Path $SearchPath -Recurse -Filter "*.msi" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like "*TeamViewer*Host*.msi"
        } |
        Select-Object -First 1

    if ($FallbackMatch) {
        return $FallbackMatch.FullName
    }

    throw "Could not locate TeamViewer Host MSI under '$SearchPath'."
}

function New-TeamViewerMsiArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MsiPath,

        [Parameter()]
        [string]$CustomConfigId,

        [Parameter()]
        [string]$ApiToken,

        [Parameter()]
        [string]$AssignmentId,

        [Parameter()]
        [string]$AssignmentOptions
    )

    $Arguments = [System.Collections.Generic.List[string]]::new()

    $Arguments.Add("/i") | Out-Null
    $Arguments.Add("`"$MsiPath`"") | Out-Null
    $Arguments.Add("/qn") | Out-Null
    $Arguments.Add("/norestart") | Out-Null

    if ($CustomConfigId) {
        $Arguments.Add("CUSTOMCONFIGID=$CustomConfigId") | Out-Null
    }

    if ($ApiToken) {
        $Arguments.Add("APITOKEN=$ApiToken") | Out-Null
    }

    if ($AssignmentId) {
        $Arguments.Add("ASSIGNMENTID=$AssignmentId") | Out-Null
    }

    if ($AssignmentOptions) {
        $Arguments.Add("ASSIGNMENTOPTIONS=`"$AssignmentOptions`"") | Out-Null
    }

    return ($Arguments -join " ")
}

function Install-TeamViewerHostMsi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MsiPath,

        [Parameter(Mandatory = $true)]
        [string]$MsiArguments
    )

    if ($PSCmdlet.ShouldProcess($MsiPath, "Install TeamViewer Host")) {
        Write-Log "Starting TeamViewer Host installation."
        Write-Log "MSI path: $MsiPath"

        $Process = Start-Process `
            -FilePath "msiexec.exe" `
            -ArgumentList $MsiArguments `
            -Wait `
            -PassThru `
            -WindowStyle Hidden

        Write-Log "msiexec exit code: $($Process.ExitCode)"

        $SuccessfulExitCodes = @(0, 3010)

        if ($Process.ExitCode -notin $SuccessfulExitCodes) {
            throw "TeamViewer Host installation failed with exit code $($Process.ExitCode)."
        }

        if ($Process.ExitCode -eq 3010) {
            Write-Log "Installation completed and requires restart." "WARN"
        }
    }
}

function Remove-InstallerFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -Path $Path) {
        if ($PSCmdlet.ShouldProcess($Path, "Remove installer working directory")) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        }
    }
}

try {
    Write-Log "Starting TeamViewer Host deployment."

    if (-not (Test-IsAdministrator)) {
        throw "This script must run with administrative rights."
    }

    $InstallStateBefore = Get-TeamViewerInstallState

    if ($InstallStateBefore.IsInstalled) {
        Write-Log "TeamViewer Host is already installed: $($InstallStateBefore.DisplayName) $($InstallStateBefore.DisplayVersion)"
        Write-Log "Continuing because deployment may need to update or reapply assignment settings."
    }

    New-DirectoryIfMissing -Path $WorkPath

    $PackageFileName = Get-FileNameFromUrl -Url $DownloadUrl
    $PackagePath = Join-Path -Path $WorkPath -ChildPath $PackageFileName

    Save-RemoteFile -SourceUrl $DownloadUrl -DestinationPath $PackagePath
    Expand-TeamViewerPackage -PackagePath $PackagePath -DestinationPath $WorkPath

    $MsiPath = Find-TeamViewerHostMsi -SearchPath $WorkPath

    $MsiArguments = New-TeamViewerMsiArguments `
        -MsiPath $MsiPath `
        -CustomConfigId $CustomConfigId `
        -ApiToken $ApiToken `
        -AssignmentId $AssignmentId `
        -AssignmentOptions $AssignmentOptions

    Install-TeamViewerHostMsi -MsiPath $MsiPath -MsiArguments $MsiArguments

    $InstallStateAfter = Get-TeamViewerInstallState

    if ($InstallStateAfter.IsInstalled) {
        Write-Log "TeamViewer Host installation detected: $($InstallStateAfter.DisplayName) $($InstallStateAfter.DisplayVersion)"
    }
    else {
        Write-Log "TeamViewer Host installation was not detected in uninstall registry after msiexec completed." "WARN"
    }

    if (-not $KeepInstallerFiles) {
        Remove-InstallerFiles -Path $WorkPath
    }
    else {
        Write-Log "Keeping installer files because KeepInstallerFiles was specified."
    }

    Write-Log "TeamViewer Host deployment completed."
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    exit 1
}
