# Microsoft Graph Sign-In Activity Notes

The `Export-EntraUserSignInLicenseReport.ps1` script uses Microsoft Graph PowerShell to retrieve user, license, and sign-in activity data from Microsoft Entra ID.

## Important Caveats

Sign-in activity data can be extremely useful for stale account review and license cleanup, but it should not be treated as perfect by itself.

Consider the following before making cleanup decisions:

- Some sign-in fields may be blank depending on licensing, permissions, retention, and data availability.
- `lastSuccessfulSignInDateTime` was not historically backfilled, so older accounts may not show older successful sign-ins.
- `lastSignInDateTime` may represent attempted sign-ins, not only successful sign-ins.
- Non-interactive sign-ins can represent background service or token activity and should be reviewed separately from interactive user activity.
- Exchange Online mailbox activity is not the same thing as Microsoft Entra ID sign-in activity.
- A blank sign-in value does not automatically mean an account is safe to disable or delete.

## Recommended Review Approach

Use sign-in activity as one signal alongside other account and business context, such as:

- Account enabled/disabled state
- Assigned licenses
- User type
- Manager
- Department
- Mailbox or workload activity
- Group membership
- Ownership of Microsoft 365 groups, Teams, SharePoint sites, apps, or automation
- HR or identity lifecycle status

## Practical Guidance

For cleanup or license review projects:

1. Export the report.
2. Identify stale or suspicious accounts.
3. Validate with business owners or managers.
4. Remove or downgrade licenses before deleting accounts when appropriate.
5. Disable or block sign-in before deletion for higher-risk cleanup.
6. Retain documentation of decisions for audit or change control.

## Summary

The goal is not just to pull a timestamp from Microsoft Graph. The goal is to understand what that timestamp means, where the data has gaps, and how to use it safely for operational decisions.
