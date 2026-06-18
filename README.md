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
