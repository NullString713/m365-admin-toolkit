<#
.SYNOPSIS
Populates Intune deployment ring groups with location-aware device distribution.

.DESCRIPTION
This Azure Automation runbook connects to Microsoft Graph using app-only authentication,
clears existing device memberships from Intune deployment ring groups, and repopulates
those groups with corporate-owned devices.

The script is designed to reduce broad-impact endpoint change risk. Instead of assigning
all devices from a location, state, region, site, or business unit to the same deployment wave,
it processes each source bucket independently and spreads that bucket's devices across the
available deployment rings.

This supports two common endpoint ownership patterns:

1. User-affinity devices
   - Source groups contain users.
   - The script reads each user's owned devices.
   - Corporate-owned devices are distributed across deployment rings.

2. No-user-affinity devices
   - Source groups contain device objects directly.
   - Use this for shared, kiosk, self-deploying, lab, warehouse, or other no-user-affinity devices.
   - Corporate-owned devices are distributed across deployment rings.

This helps phased Intune rollouts avoid impacting an entire location or device population at once.

.PARAMETER TenantId
The Microsoft Entra tenant ID.

.PARAMETER ClientId
The application/client ID of the Entra app registration used for Microsoft Graph authentication.

.PARAMETER ClientSecretAutomationVariableName
The Azure Automation variable name containing the app registration client secret.

.PARAMETER NestedUserLocationGroupIds
Parent group IDs that contain child location/state/site/business-unit groups.
The child groups should contain users.

.PARAMETER DirectUserLocationGroupIds
Group IDs that directly contain users and should be processed as their own location buckets.

.PARAMETER DirectDeviceLocationGroupIds
Group IDs that directly contain device objects. Use this for shared, kiosk, self-deploying,
lab, warehouse, or no-user-affinity devices.

.PARAMETER DeploymentRingGroupIds
The Intune deployment ring group IDs to populate. Devices from each source bucket are spread across these rings.

.PARAMETER SkipClearExistingMembers
Skips clearing existing device memberships from the deployment ring groups before adding devices.

.EXAMPLE
.\Update-IntuneDeploymentRings.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -ClientId "00000000-0000-0000-0000-000000000000" `
  -ClientSecretAutomationVariableName "GraphClientSecret" `
  -NestedUserLocationGroupIds @(
    "11111111-1111-1111-1111-111111111111",
    "22222222-2222-2222-2222-222222222222"
  ) `
  -DirectUserLocationGroupIds @(
    "33333333-3333-3333-3333-333333333333"
  ) `
  -DirectDeviceLocationGroupIds @(
    "44444444-4444-4444-4444-444444444444"
  ) `
  -DeploymentRingGroupIds @(
    "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    "cccccccc-cccc-cccc-cccc-cccccccccccc",
    "dddddddd-dddd-dddd-dddd-dddddddddddd"
  )

.NOTES
Author: Hali
Version: 1.0

Designed for:
- Azure Automation runbooks
- Microsoft Graph PowerShell SDK
- App-only Microsoft Graph authentication
- Intune deployment rings based on Entra security groups

Typical Microsoft Graph application permissions may include:
- GroupMember.ReadWrite.All
- Group.Read.All or Group.ReadWrite.All
- User.Read.All
- Device.Read.All

Review least-privilege permissions and change-control requirements before using in production.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ClientSecretAutomationVariableName = "GraphClientSecret",

    [Parameter()]
    [string[]]$NestedUserLocationGroupIds = @(),

    [Parameter()]
    [string[]]$DirectUserLocationGroupIds = @(),

    [Parameter()]
    [string[]]$DirectDeviceLocationGroupIds = @(),

    [Parameter(Mandatory = $true)]
    [ValidateCount(2, 20)]
    [string[]]$DeploymentRingGroupIds,

    [Parameter()]
    [switch]$SkipClearExistingMembers
)

$ErrorActionPreference = "Stop"

function Connect-GraphFromAutomationVariable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecretAutomationVariableName
    )

    try {
        $ClientSecret = Get-AutomationVariable -Name $ClientSecretAutomationVariableName -ErrorAction Stop
    }
    catch {
        throw "Could not read Azure Automation variable '$ClientSecretAutomationVariableName'. Confirm the variable exists and contains the app registration client secret."
    }

    $SecureClientSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
    $ClientSecretCredential = [System.Management.Automation.PSCredential]::new($ClientId, $SecureClientSecret)

    Write-Output "Connecting to Microsoft Graph..."
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientSecretCredential | Out-Null
}

function Get-DirectoryObjectType {
    param(
        [Parameter(Mandatory = $true)]
        [object]$DirectoryObject
    )

    if ($DirectoryObject.AdditionalProperties -and $DirectoryObject.AdditionalProperties.ContainsKey("@odata.type")) {
        return $DirectoryObject.AdditionalProperties["@odata.type"]
    }

    if ($DirectoryObject.PSObject.Properties.Name -contains "OdataType") {
        return $DirectoryObject.OdataType
    }

    return $null
}

function Get-GroupMembers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId
    )

    return @(Get-MgBetaGroupMember -GroupId $GroupId -All -ConsistencyLevel eventual)
}

function Get-LocationBuckets {
    param(
        [Parameter()]
        [string[]]$NestedUserLocationGroupIds = @(),

        [Parameter()]
        [string[]]$DirectUserLocationGroupIds = @(),

        [Parameter()]
        [string[]]$DirectDeviceLocationGroupIds = @()
    )

    $LocationBuckets = [System.Collections.Generic.List[object]]::new()

    foreach ($ParentGroupId in $NestedUserLocationGroupIds) {
        Write-Output "Reading child user-location groups from parent group $ParentGroupId..."

        $ChildGroups = Get-GroupMembers -GroupId $ParentGroupId

        foreach ($ChildGroup in $ChildGroups) {
            $ObjectType = Get-DirectoryObjectType -DirectoryObject $ChildGroup

            if ($ObjectType -notlike "*microsoft.graph.group") {
                continue
            }

            $LocationBuckets.Add([PSCustomObject]@{
                GroupId    = $ChildGroup.Id
                BucketType = "User"
                Source     = "NestedUserLocationGroup"
            }) | Out-Null
        }
    }

    foreach ($DirectUserGroupId in $DirectUserLocationGroupIds) {
        $LocationBuckets.Add([PSCustomObject]@{
            GroupId    = $DirectUserGroupId
            BucketType = "User"
            Source     = "DirectUserLocationGroup"
        }) | Out-Null
    }

    foreach ($DirectDeviceGroupId in $DirectDeviceLocationGroupIds) {
        $LocationBuckets.Add([PSCustomObject]@{
            GroupId    = $DirectDeviceGroupId
            BucketType = "Device"
            Source     = "DirectDeviceLocationGroup"
        }) | Out-Null
    }

    return @($LocationBuckets)
}

function Get-CorporateOwnedDevicesFromUserLocationGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserLocationGroupId
    )

    $DevicesById = @{}

    Write-Output "Reading users from user-location group $UserLocationGroupId..."
    $Members = Get-GroupMembers -GroupId $UserLocationGroupId

    foreach ($Member in $Members) {
        $ObjectType = Get-DirectoryObjectType -DirectoryObject $Member

        if ($ObjectType -notlike "*microsoft.graph.user") {
            continue
        }

        Write-Output "Reading owned devices for user $($Member.Id)..."

        try {
            $UserDevices = @(Get-MgBetaUserOwnedDevice -UserId $Member.Id -All -ConsistencyLevel eventual -ErrorAction Stop)
        }
        catch {
            Write-Warning "Could not read owned devices for user $($Member.Id). $($_.Exception.Message)"
            continue
        }

        foreach ($UserDevice in $UserDevices) {
            if (-not $UserDevice.Id -or $DevicesById.ContainsKey($UserDevice.Id)) {
                continue
            }

            try {
                $Device = Get-MgBetaDevice -DeviceId $UserDevice.Id -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not read device $($UserDevice.Id). $($_.Exception.Message)"
                continue
            }

            if ($Device.DeviceOwnership -eq "Personal") {
                Write-Output "Skipping personal device $($Device.DisplayName) <$($Device.Id)>."
                continue
            }

            $DevicesById[$Device.Id] = [PSCustomObject]@{
                DeviceId        = $Device.Id
                DeviceName      = $Device.DisplayName
                OperatingSystem = $Device.OperatingSystem
                DeviceOwnership = $Device.DeviceOwnership
                SourceType      = "UserOwnedDevice"
                SourceGroupId   = $UserLocationGroupId
                UserId          = $Member.Id
            }
        }
    }

    return @($DevicesById.Values)
}

function Get-CorporateOwnedDevicesFromDeviceLocationGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceLocationGroupId
    )

    $DevicesById = @{}

    Write-Output "Reading devices from device-location group $DeviceLocationGroupId..."
    $Members = Get-GroupMembers -GroupId $DeviceLocationGroupId

    foreach ($Member in $Members) {
        $ObjectType = Get-DirectoryObjectType -DirectoryObject $Member

        if ($ObjectType -notlike "*microsoft.graph.device") {
            continue
        }

        try {
            $Device = Get-MgBetaDevice -DeviceId $Member.Id -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not read device $($Member.Id). $($_.Exception.Message)"
            continue
        }

        if ($Device.DeviceOwnership -eq "Personal") {
            Write-Output "Skipping personal device $($Device.DisplayName) <$($Device.Id)>."
            continue
        }

        if ($DevicesById.ContainsKey($Device.Id)) {
            continue
        }

        $DevicesById[$Device.Id] = [PSCustomObject]@{
            DeviceId        = $Device.Id
            DeviceName      = $Device.DisplayName
            OperatingSystem = $Device.OperatingSystem
            DeviceOwnership = $Device.DeviceOwnership
            SourceType      = "DirectDeviceGroupMember"
            SourceGroupId   = $DeviceLocationGroupId
            UserId          = $null
        }
    }

    return @($DevicesById.Values)
}

function Clear-DeploymentRingDeviceMembers {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$DeploymentRingGroupIds
    )

    foreach ($DeploymentRingGroupId in $DeploymentRingGroupIds) {
        Write-Output "Reading existing members from deployment ring group $DeploymentRingGroupId..."
        $ExistingMembers = Get-GroupMembers -GroupId $DeploymentRingGroupId

        foreach ($Member in $ExistingMembers) {
            $ObjectType = Get-DirectoryObjectType -DirectoryObject $Member

            if ($ObjectType -notlike "*microsoft.graph.device") {
                Write-Output "Skipping non-device member $($Member.Id) in deployment ring group $DeploymentRingGroupId."
                continue
            }

            if ($PSCmdlet.ShouldProcess($DeploymentRingGroupId, "Remove device member $($Member.Id)")) {
                Remove-MgBetaGroupMemberByRef -GroupId $DeploymentRingGroupId -DirectoryObjectId $Member.Id -ErrorAction Stop
            }
        }
    }
}

function Add-DeviceToDeploymentRing {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeploymentRingGroupId,

        [Parameter(Mandatory = $true)]
        [string]$DeviceId
    )

    if ($PSCmdlet.ShouldProcess($DeploymentRingGroupId, "Add device $DeviceId")) {
        New-MgGroupMember -GroupId $DeploymentRingGroupId -DirectoryObjectId $DeviceId -ErrorAction Stop
    }
}

$SourceGroupCount = $NestedUserLocationGroupIds.Count + $DirectUserLocationGroupIds.Count + $DirectDeviceLocationGroupIds.Count

if ($SourceGroupCount -eq 0) {
    throw "Provide at least one nested user-location group, direct user-location group, or direct device-location group ID."
}

Connect-GraphFromAutomationVariable `
    -TenantId $TenantId `
    -ClientId $ClientId `
    -ClientSecretAutomationVariableName $ClientSecretAutomationVariableName

if (-not $SkipClearExistingMembers) {
    Clear-DeploymentRingDeviceMembers -DeploymentRingGroupIds $DeploymentRingGroupIds
}
else {
    Write-Output "Skipping deployment ring cleanup because SkipClearExistingMembers was specified."
}

$LocationBuckets = Get-LocationBuckets `
    -NestedUserLocationGroupIds $NestedUserLocationGroupIds `
    -DirectUserLocationGroupIds $DirectUserLocationGroupIds `
    -DirectDeviceLocationGroupIds $DirectDeviceLocationGroupIds

Write-Output "Found $($LocationBuckets.Count) location bucket(s) to process."

$RingCounts = @{}
$AssignedDeviceIds = @{}

foreach ($DeploymentRingGroupId in $DeploymentRingGroupIds) {
    $RingCounts[$DeploymentRingGroupId] = 0
}

foreach ($LocationBucket in $LocationBuckets) {
    Write-Output "Processing $($LocationBucket.Source) bucket $($LocationBucket.GroupId)..."

    if ($LocationBucket.BucketType -eq "Device") {
        $EligibleDevices = Get-CorporateOwnedDevicesFromDeviceLocationGroup -DeviceLocationGroupId $LocationBucket.GroupId
    }
    else {
        $EligibleDevices = Get-CorporateOwnedDevicesFromUserLocationGroup -UserLocationGroupId $LocationBucket.GroupId
    }

    if ($EligibleDevices.Count -eq 0) {
        Write-Output "No eligible corporate-owned devices found for bucket $($LocationBucket.GroupId)."
        continue
    }

    $UnassignedDevices = @(
        $EligibleDevices | Where-Object {
            -not $AssignedDeviceIds.ContainsKey($_.DeviceId)
        }
    )

    if ($UnassignedDevices.Count -eq 0) {
        Write-Output "All eligible devices from bucket $($LocationBucket.GroupId) were already assigned from another source bucket."
        continue
    }

    Write-Output "Distributing $($UnassignedDevices.Count) device(s) from bucket $($LocationBucket.GroupId) across deployment rings."

    $ShuffledDevices = @($UnassignedDevices | Sort-Object { Get-Random })
    $RingIndex = Get-Random -Minimum 0 -Maximum $DeploymentRingGroupIds.Count

    foreach ($Device in $ShuffledDevices) {
        $TargetDeploymentRingGroupId = $DeploymentRingGroupIds[$RingIndex]

        Add-DeviceToDeploymentRing `
            -DeploymentRingGroupId $TargetDeploymentRingGroupId `
            -DeviceId $Device.DeviceId

        $AssignedDeviceIds[$Device.DeviceId] = $true
        $RingCounts[$TargetDeploymentRingGroupId]++

        $RingIndex = ($RingIndex + 1) % $DeploymentRingGroupIds.Count
    }
}

Write-Output "Deployment ring population complete."
Write-Output "Total unique devices assigned: $($AssignedDeviceIds.Count)"

foreach ($DeploymentRingGroupId in $DeploymentRingGroupIds) {
    Write-Output "Deployment ring group $DeploymentRingGroupId received $($RingCounts[$DeploymentRingGroupId]) device(s)."
}
