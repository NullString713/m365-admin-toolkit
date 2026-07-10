# Microsoft 365 Admin Toolkit

Practical PowerShell examples for Microsoft 365, Entra ID, Intune, endpoint deployment, reporting, remediation, and operational automation.

This repo is a public-safe collection of scripts and notes based on real enterprise IT workflows. Scripts are generalized, parameterized, and cleaned of organization-specific values.

## Focus Areas

- Microsoft Entra ID reporting
- Microsoft 365 license review and cleanup
- Intune endpoint deployment workflows
- Endpoint compliance and remediation support
- Autopilot device registration workflows
- Third-party endpoint software deployment
- Microsoft Graph PowerShell automation

## Scripts

### Entra ID

| Script | Description |
|---|---|
| [`Export-EntraUserSignInLicenseReport.ps1`](./entra-id/Export-EntraUserSignInLicenseReport.ps1) | Exports Entra user details, assigned licenses, and sign-in activity to CSV using Microsoft Graph PowerShell. |

### Intune

| Script | Description |
|---|---|
| [`Update-IntuneDeploymentRings.ps1`](./intune/Update-IntuneDeploymentRings.ps1) | Populates Intune deployment ring groups using location-aware device distribution. Supports user-affinity devices, no-user-affinity device groups, corporate-owned device filtering, Azure Automation app-only authentication, and phased rollout patterns designed to reduce broad-impact endpoint change risk. |
| [`Enable-LenovoSecureBoot.ps1`](./intune/Enable-LenovoSecureBoot.ps1) | Detects and remediates Lenovo Secure Boot state using Lenovo WMI BIOS classes. Designed as a public-safe Intune remediation example with logging, detection mode, and optional restart messaging. |
| [`Install-TeamViewerHost.ps1`](./intune/Install-TeamViewerHost.ps1) | Downloads, extracts, installs, and optionally assigns TeamViewer Host using parameterized deployment values. Designed as a public-safe endpoint software deployment example for Intune or similar management tools. |
| [`Export-AutopilotHardwareHash.ps1`](./intune/Export-AutopilotHardwareHash.ps1) | Collects Autopilot hardware hash data from a local Windows device, exports individual per-device CSV files, and automatically rebuilds a combined import-ready CSV for technician-driven or USB-based device staging workflows. |

## Usage Examples

### Entra ID sign-in and license report

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

### Intune deployment ring automation

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

### Lenovo Secure Boot remediation

Run detection only:

```powershell
.\intune\Enable-LenovoSecureBoot.ps1 -DetectOnly
```

Attempt remediation:

```powershell
.\intune\Enable-LenovoSecureBoot.ps1
```

Preview remediation safely:

```powershell
.\intune\Enable-LenovoSecureBoot.ps1 -WhatIf
```

### TeamViewer Host deployment

Run with placeholder deployment values:

```powershell
.\intune\Install-TeamViewerHost.ps1 `
  -DownloadUrl "https://example.com/TeamViewer_MSI32.zip" `
  -CustomConfigId "REDACTED_CUSTOM_CONFIG_ID" `
  -ApiToken "REDACTED_API_TOKEN" `
  -AssignmentOptions "--grant-easy-access --reassign"
```

Preview safely:

```powershell
.\intune\Install-TeamViewerHost.ps1 `
  -DownloadUrl "https://example.com/TeamViewer_MSI32.zip" `
  -CustomConfigId "REDACTED_CUSTOM_CONFIG_ID" `
  -ApiToken "REDACTED_API_TOKEN" `
  -WhatIf
```

### Autopilot hardware hash batch collection

Collect the local hardware hash:

```powershell
.\intune\Export-AutopilotHardwareHash.ps1
```

Collect with a group tag:

```powershell
.\intune\Export-AutopilotHardwareHash.ps1 -GroupTag "REDACTED-GROUP-TAG"
```

Write output to a USB drive or staging folder:

```powershell
.\intune\Export-AutopilotHardwareHash.ps1 -OutputRoot "E:\Autopilot"
```

Rebuild the combined CSV from existing individual device CSV files:

```powershell
.\intune\Export-AutopilotHardwareHash.ps1 -CombineOnly
```

## Documentation

| Document | Description |
|---|---|
| [`Microsoft Graph Sign-In Activity Notes`](./docs/graph-signin-activity-notes.md) | Notes on sign-in activity fields, reporting considerations, and Graph PowerShell usage. |

## Requirements

Most scripts require some combination of:

- Windows PowerShell or PowerShell 7
- Microsoft Graph PowerShell SDK
- Administrative rights on the endpoint
- Intune, Entra ID, or Microsoft 365 permissions appropriate to the task
- Approved change-control and testing before production use

Install the Microsoft Graph PowerShell module:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

Some scripts may require beta Graph cmdlets or endpoint-specific vendor support, such as Lenovo WMI BIOS classes.

## Security Notes

This repo intentionally avoids publishing real organization-specific values.

Do not commit:

- Tenant IDs
- Client IDs tied to production tenants
- Client secrets
- API tokens
- TeamViewer assignment tokens
- Custom configuration IDs
- Internal group IDs
- Internal URLs
- Private download links
- Production device names or user names

Use placeholders, environment-specific parameters, Intune assignment settings, Azure Automation variables, or an approved secret-management process.

## Disclaimer

These scripts are public examples and should be reviewed, tested, and adapted before use in any production environment.
