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

## Requirements

Most scripts require the Microsoft Graph PowerShell module.

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
