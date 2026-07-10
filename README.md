# Microsoft 365 Admin Toolkit

Practical PowerShell scripts for Microsoft 365, Microsoft Entra ID, Intune, Exchange Online, SharePoint Online, and Microsoft Graph administration.

These scripts are focused on real-world admin tasks such as tenant reporting, license cleanup, stale account review, endpoint visibility, access governance, and operational validation.

## Focus Areas

- Microsoft Entra ID reporting
- Microsoft 365 license review and cleanup
- Intune device and compliance visibility
- Conditional Access review
- Microsoft 365 group governance
- SharePoint and Teams operational cleanup
- Microsoft Graph PowerShell automation

## Scripts

### Entra ID

| Script | Description |
|---|---|
| [`Export-EntraUserSignInLicenseReport.ps1`](entra-id/Export-EntraUserSignInLicenseReport.ps1) | Exports Entra user details, assigned licenses, and sign-in activity to CSV using Microsoft Graph PowerShell. |

### Intune

| Script | Description |
|---|---|
| [`Update-IntuneDeploymentRings.ps1`](./intune/Update-IntuneDeploymentRings.ps1) | Populates Intune deployment ring groups using location-aware device distribution. Supports user-affinity devices, no-user-affinity device groups, corporate-owned device filtering, Azure Automation app-only authentication, and phased rollout patterns designed to reduce broad-impact endpoint change risk. |
## Usage

Run the Entra user sign-in and license report:

```powershell
.\entra-id\Export-EntraUserSignInLicenseReport.ps1
```

Include manager information:

```powershell
.\entra-id\Export-EntraUserSignInLicenseReport.ps1 -IncludeManager
```

Specify a custom output path:

```powershell
.\entra-id\Export-EntraUserSignInLicenseReport.ps1 -OutputPath ".\reports\EntraUserSignInLicenseReport.csv"
```
Run the Intune deployment ring automation:

```powershell
.\intune\Update-IntuneDeploymentRings.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -ClientId "00000000-0000-0000-0000-000000000000" `
  -ClientSecretAutomationVariableName "GraphClientSecret" `
  -NestedUserLocationGroupIds @(
    "11111111-1111-1111-1111-111111111111"
  ) `
  -DirectUserLocationGroupIds @(
    "22222222-2222-2222-2222-222222222222"
  ) `
  -DirectDeviceLocationGroupIds @(
    "33333333-3333-3333-3333-333333333333"
  ) `
  -DeploymentRingGroupIds @(
    "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    "cccccccc-cccc-cccc-cccc-cccccccccccc",
    "dddddddd-dddd-dddd-dddd-dddddddddddd"
  )
```

Preview changes safely with `-WhatIf`:

```powershell
.\intune\Update-IntuneDeploymentRings.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -ClientId "00000000-0000-0000-0000-000000000000" `
  -ClientSecretAutomationVariableName "GraphClientSecret" `
  -DirectDeviceLocationGroupIds @(
    "33333333-3333-3333-3333-333333333333"
  ) `
  -DeploymentRingGroupIds @(
    "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    "cccccccc-cccc-cccc-cccc-cccccccccccc",
    "dddddddd-dddd-dddd-dddd-dddddddddddd"
  ) `
  -WhatIf
```

## Documentation

| Document | Description |
|---|---|
| [Microsoft Graph Sign-In Activity Notes](docs/graph-signin-activity-notes.md) | Notes on sign-in activity fields, reporting caveats, and safe cleanup decisions. |
## Requirements

Most scripts require the Microsoft Graph PowerShell module.

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

Specific permissions are listed in each script header.

## Notes

These scripts are intended as practical examples and starting points. Review the code, validate required permissions, and test in a safe environment before using in production.

Some Microsoft Graph properties may have licensing, permission, retention, or data availability limitations. Always validate output before making cleanup, licensing, or access decisions.

## Disclaimer

These scripts are provided as-is with no warranty. Use at your own risk.
