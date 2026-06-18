<#
.SYNOPSIS
Exports Microsoft Entra ID user sign-in activity and license assignments to CSV.

.DESCRIPTION
Retrieves users from Microsoft Graph, including account status, assigned licenses,
and sign-in activity where available. Maps license SKU IDs to friendly SKU part names
using tenant subscribed SKU data.

Useful for Microsoft 365 license reviews, stale account analysis,
audit preparation, and tenant cleanup planning.

.REQUIREMENTS
- Microsoft.Graph PowerShell module
- Microsoft Entra ID P1 or P2 for signInActivity
- Graph permissions:
  - User.Read.All
  - Directory.Read.All
  - AuditLog.Read.All
  - Organization.Read.All

.NOTES
lastSuccessfulSignInDateTime is not backfilled before Dec. 1, 2023.
Some sign-in fields may be blank depending on licensing, permissions, user activity,
and data availability.
#>

[CmdletBinding()]
param(
    [string]$OutputPath = ".\EntraUserSignInLicenseReport.csv",

    [switch]$IncludeManager
)

function ConvertTo-FriendlyDate {
    param(
        [Parameter(Mandatory = $false)]
        $DateValue
    )

    if ([string]::IsNullOrWhiteSpace($DateValue)) {
        return $null
    }

    try {
        return ([datetime]$DateValue).ToString("yyyy-MM-dd HH:mm:ss")
    }
    catch {
        return $DateValue
    }
}

function Get-LicenseMap {
    Write-Host "Retrieving tenant subscribed SKUs..." -ForegroundColor Cyan

    $skuMap = @{}
    $subscribedSkus = Get-MgSubscribedSku -All

    foreach ($sku in $subscribedSkus) {
        $skuMap[$sku.SkuId.ToString()] = $sku.SkuPartNumber
    }

    return $skuMap
}

function Get-FriendlyLicenseNames {
    param(
        [Parameter(Mandatory = $false)]
        $AssignedLicenses,

        [Parameter(Mandatory = $true)]
        [hashtable]$SkuMap
    )

    if (-not $AssignedLicenses -or $AssignedLicenses.Count -eq 0) {
        return $null
    }

    $licenseNames = foreach ($license in $AssignedLicenses) {
        $skuId = $license.SkuId.ToString()

        if ($SkuMap.ContainsKey($skuId)) {
            $SkuMap[$skuId]
        }
        else {
            "Unknown SKU: $skuId"
        }
    }

    return ($licenseNames | Sort-Object) -join "; "
}

function Get-UserManagerSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    try {
        $manager = Get-MgUserManager -UserId $UserId -ErrorAction Stop

        if ($manager.AdditionalProperties) {
            $managerDisplayName = $manager.AdditionalProperties["displayName"]
            $managerUpn = $manager.AdditionalProperties["userPrincipalName"]

            if ($managerDisplayName -and $managerUpn) {
                return "$managerDisplayName <$managerUpn>"
            }

            if ($managerDisplayName) {
                return $managerDisplayName
            }

            if ($managerUpn) {
                return $managerUpn
            }
        }

        return $manager.Id
    }
    catch {
        return $null
    }
}

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

$requiredScopes = @(
    "User.Read.All",
    "Directory.Read.All",
    "AuditLog.Read.All",
    "Organization.Read.All"
)

Connect-MgGraph -Scopes $requiredScopes | Out-Null

$context = Get-MgContext
Write-Host "Connected as: $($context.Account)" -ForegroundColor Green
Write-Host "Tenant ID: $($context.TenantId)" -ForegroundColor Green

$licenseMap = Get-LicenseMap

Write-Host "Retrieving users from Microsoft Graph..." -ForegroundColor Cyan

$userProperties = @(
    "id",
    "displayName",
    "userPrincipalName",
    "mail",
    "userType",
    "accountEnabled",
    "createdDateTime",
    "department",
    "jobTitle",
    "assignedLicenses",
    "signInActivity"
)

$users = Get-MgUser -All -Property $userProperties

Write-Host "Processing $($users.Count) users..." -ForegroundColor Cyan

$report = foreach ($user in $users) {
    $signInActivity = $user.SignInActivity

    $licenseNames = Get-FriendlyLicenseNames `
        -AssignedLicenses $user.AssignedLicenses `
        -SkuMap $licenseMap

    $managerSummary = $null

    if ($IncludeManager) {
        $managerSummary = Get-UserManagerSummary -UserId $user.Id
    }

    [PSCustomObject]@{
        DisplayName                         = $user.DisplayName
        UserPrincipalName                   = $user.UserPrincipalName
        Mail                                = $user.Mail
        UserType                            = $user.UserType
        AccountEnabled                      = $user.AccountEnabled
        CreatedDateTime                     = ConvertTo-FriendlyDate $user.CreatedDateTime
        Department                          = $user.Department
        JobTitle                            = $user.JobTitle
        Manager                             = $managerSummary
        AssignedLicenseCount                = if ($user.AssignedLicenses) { $user.AssignedLicenses.Count } else { 0 }
        AssignedLicenses                    = $licenseNames
        LastSuccessfulSignInDateTime        = ConvertTo-FriendlyDate $signInActivity.LastSuccessfulSignInDateTime
        LastSignInDateTime                  = ConvertTo-FriendlyDate $signInActivity.LastSignInDateTime
        LastNonInteractiveSignInDateTime    = ConvertTo-FriendlyDate $signInActivity.LastNonInteractiveSignInDateTime
        LastSuccessfulSignInRequestId       = $signInActivity.LastSuccessfulSignInRequestId
        LastSignInRequestId                 = $signInActivity.LastSignInRequestId
        LastNonInteractiveSignInRequestId   = $signInActivity.LastNonInteractiveSignInRequestId
    }
}

$report |
    Sort-Object AccountEnabled, UserPrincipalName |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Report complete." -ForegroundColor Green
Write-Host "Output path: $OutputPath" -ForegroundColor Green
