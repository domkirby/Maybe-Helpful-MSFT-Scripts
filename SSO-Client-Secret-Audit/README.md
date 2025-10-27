# Entra ID Application Credentials Audit Script

A PowerShell script for auditing Microsoft Entra ID (formerly Azure AD) enterprise applications to identify expiring OAuth client secrets, certificates, and SAML signing certificates. The script provides comprehensive reporting with color-coded alerts for credentials requiring immediate attention.

## Features

- ✅ **Comprehensive Credential Auditing**: Scans OAuth client secrets, key certificates, and SAML signing certificates
- 🎯 **Prioritized Reporting**: Automatically sorts credentials by expiration date (soonest first)
- 🚨 **Visual Alerts**: Color-coded status indicators for easy identification of urgent items
- 📊 **Multiple Export Formats**: Generates both CSV and professionally-styled HTML reports
- 🖨️ **PDF-Ready**: HTML output is optimized for print-to-PDF conversion
- 🔒 **Minimal Permissions**: Uses only the required `Application.Read.All` scope
- 📈 **Summary Statistics**: Provides counts of expired, critical, warning, and OK credentials
- 🎨 **Professional Styling**: Clean, modern HTML design with responsive layout

## Status Categories

The script categorizes credentials into four status levels:

| Status | Days Until Expiry | Description |
|--------|------------------|-------------|
| 🔴 **EXPIRED** | < 0 days | Credential has already expired |
| 🟠 **CRITICAL** | 0-30 days | Requires immediate action |
| 🟡 **WARNING** | 31-60 days | Plan renewal soon |
| 🟢 **OK** | > 60 days | No immediate action needed |

## Prerequisites

### PowerShell Version
- **PowerShell 7.0 or higher** (recommended)
- PowerShell 5.1 is supported but PowerShell 7+ is preferred

### Required PowerShell Module
Install the Microsoft Graph PowerShell SDK:

```powershell
# Option 1: Install only the required module (recommended)
Install-Module Microsoft.Graph.Applications -Scope CurrentUser

# Option 2: Install the complete Microsoft Graph module collection
Install-Module Microsoft.Graph -Scope CurrentUser
```

### Required Entra ID Roles

To run this script, the user account must have one of the following Entra ID roles:

#### Recommended (Read-Only)
- **Global Reader** ⭐ *Best choice for auditing* - Provides read-only access to all tenant information
- **Cloud Application Administrator** - Can read all application registrations
- **Application Administrator** - Can read all application registrations

#### Also Supported (Higher Privileges)
- **Global Administrator** - Full tenant access (not recommended for read-only tasks)
- **Privileged Role Administrator** - Can manage role assignments

> **Note**: The `Directory Readers` role does **NOT** provide sufficient permissions to read credential metadata.

### Microsoft Graph API Permissions

The script requires the following Microsoft Graph API scope:
- `Application.Read.All` - Read all application registration and service principal information

This permission is automatically requested when the script runs and connects to Microsoft Graph.

## Installation

1. **Download the script**:
   ```powershell
   # Clone the repository
   git clone https://github.com/domkirby/Maybe-Helpful-MSFT-Scripts.git
   cd Maybe-Helpful-MSFT-Scripts
   ```
   **You can also download this script in particular from the GitHub download button**

2. **Install required module**:
   ```powershell
   Install-Module Microsoft.Graph.Applications -Scope CurrentUser
   ```
   If you'd prefer, you can install all of ``Microsoft.Graph``, but this script only requires ``Applications``

   ```powershell
   Install-Module Microsoft.Graph -Scope CurrentUser
   ```

3. **Verify installation**:
   ```powershell
   Get-InstalledModule Microsoft.Graph.Applications
   ```

## Usage

**Notice**: This script is unsigned, so you may need to update your ``ExecutionPolicy`` or review and sign the script yourself.

### Basic Usage

Run the script with default settings (uses your default tenant):

```powershell
.\Audit-EntraIDAppCredentials.ps1
```

### Specify Tenant ID

Connect to a specific tenant:

```powershell
.\Audit-EntraIDAppCredentials.ps1 -TenantId "12345678-1234-1234-1234-123456789abc"
```

### Export Results

Generate CSV and HTML reports:

```powershell
.\Audit-EntraIDAppCredentials.ps1 -ExportPath "C:\Reports\AppCredentials"
```

This creates:
- `C:\Reports\AppCredentials.csv` - Data file for Excel/analysis
- `C:\Reports\AppCredentials.html` - Styled report ready for viewing/printing

### Complete Example

```powershell
.\Audit-EntraIDAppCredentials.ps1 `
    -TenantId "12345678-1234-1234-1234-123456789abc" `
    -ExportPath "C:\AuditReports\$(Get-Date -Format 'yyyyMMdd')_AppCredentials"
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `TenantId` | String | No | The Entra ID tenant ID to audit. If not specified, uses the default tenant. |
| `ExportPath` | String | No | Base path for exporting reports. Omit file extension - script creates both .csv and .html files. |

## Output

### Console Output

The script provides real-time console output with:
- Connection status and tenant information
- Progress indicators during data retrieval
- Summary statistics with color-coded counts
- Detailed listing of credentials expiring within 60 days
- Formatted table of all credentials sorted by expiry date

### CSV Export

The CSV file includes the following columns:
- `ApplicationName` - Display name of the application
- `ApplicationId` - Application (client) ID
- `ObjectId` - Object ID in Entra ID
- `CredentialType` - Type of credential (Client Secret, Certificate, SAML Signing Certificate)
- `CredentialId` - Unique identifier for the credential
- `DisplayName` - Display name/description of the credential
- `StartDate` - When the credential became valid
- `ExpiryDate` - When the credential expires
- `DaysUntilExpiry` - Days remaining until expiration
- `Status` - Current status (EXPIRED, CRITICAL, WARNING, OK)

### HTML Report

The HTML report includes:
- Report header with generation timestamp and tenant information
- Summary dashboard with visual status cards
- Alert section highlighting credentials expiring within 60 days
- Comprehensive table of all credentials with color-coded status badges
- Professional styling optimized for both screen viewing and PDF conversion

### Creating a PDF from HTML

1. Run the script with the `-ExportPath` parameter
2. Open the generated `.html` file in any web browser
3. Press `Ctrl+P` (Windows/Linux) or `Cmd+P` (Mac)
4. Select "Save as PDF" or "Microsoft Print to PDF" as the printer
5. Click "Save" to generate your PDF report

The HTML is fully styled with print media queries to ensure colors and formatting are preserved in the PDF output.

## Examples

### Example 1: Quick Audit

```powershell
# Run a quick audit and view results in console
.\Audit-EntraIDAppCredentials.ps1
```

### Example 2: Monthly Compliance Report

```powershell
# Generate monthly report with date stamp
$reportDate = Get-Date -Format "yyyy-MM"
.\Audit-EntraIDAppCredentials.ps1 -ExportPath "C:\Reports\$reportDate-Compliance"
```

### Example 3: Multi-Tenant Audit

```powershell
# Audit multiple tenants
$tenants = @(
    "tenant1-guid-here",
    "tenant2-guid-here",
    "tenant3-guid-here"
)

foreach ($tenant in $tenants) {
    .\Audit-EntraIDAppCredentials.ps1 `
        -TenantId $tenant `
        -ExportPath "C:\Reports\$tenant-$(Get-Date -Format 'yyyyMMdd')"
}
```

### Example 4: Scheduled Task

Create a scheduled task to run the audit automatically:

```powershell
$action = New-ScheduledTaskAction `
    -Execute "pwsh.exe" `
    -Argument "-File C:\Scripts\Audit-EntraIDAppCredentials.ps1 -ExportPath C:\Reports\Weekly-Audit"

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9am

Register-ScheduledTask `
    -TaskName "Weekly Entra ID Credentials Audit" `
    -Action $action `
    -Trigger $trigger `
    -Description "Weekly audit of application credentials"
```

## Troubleshooting

### Issue: "Module not found"

**Solution**: Install the required module:
```powershell
Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
```

### Issue: "Insufficient privileges"

**Error**: `Insufficient privileges to complete the operation`

**Solution**: Ensure your account has one of the required Entra ID roles (Global Reader, Application Administrator, etc.). Contact your Global Administrator to assign the appropriate role.

### Issue: "Connect-MgGraph fails"

**Solution**: Ensure you're using PowerShell 7+ and have the latest module version:
```powershell
Update-Module Microsoft.Graph.Applications
```

### Issue: "No credentials found"

**Possible causes**:
- No applications exist in the tenant
- Applications don't have any credentials configured
- Insufficient permissions to read credential metadata

**Solution**: Verify you have the correct role and try running with Global Administrator permissions to test.

### Issue: HTML export fails

**Solution**: Ensure the export directory exists and you have write permissions:
```powershell
New-Item -Path "C:\Reports" -ItemType Directory -Force
.\Audit-EntraIDAppCredentials.ps1 -ExportPath "C:\Reports\Audit"
```

## Security Considerations

- ✅ The script uses **read-only** permissions and cannot modify any credentials
- ✅ Credentials themselves (secrets/keys) are **never displayed or exported** - only metadata
- ✅ The script follows the **principle of least privilege** with minimal required scopes
- ✅ Authentication uses Microsoft's secure OAuth 2.0 flow
- ⚠️ Exported reports contain sensitive application metadata - store securely
- ⚠️ Review and restrict access to generated CSV/HTML files appropriately

## Best Practices

1. **Run regularly**: Schedule weekly or monthly audits to stay ahead of expirations
2. **Monitor critical items**: Pay immediate attention to EXPIRED and CRITICAL status credentials
3. **Plan ahead**: Address WARNING status items before they become critical
4. **Archive reports**: Keep historical reports for compliance and trend analysis
5. **Use service accounts**: For scheduled tasks, use a dedicated service account with Global Reader role
6. **Secure outputs**: Store reports in a secure location with appropriate access controls
7. **Document processes**: Maintain documentation on who is responsible for renewing credentials

## Contributing

Contributions are welcome! Please feel free to submit issues, fork the repository, and create pull requests for any improvements.

### Areas for Enhancement
- Support for filtering by application name or ID
- Email notifications for expiring credentials
- Integration with ticketing systems
- Custom threshold configuration
- Support for federated identity credentials

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

Created with ❤️ for the Azure/Entra ID community

## Acknowledgments

- Microsoft Graph PowerShell SDK team
- Microsoft Entra ID (Azure AD) documentation
- The PowerShell community
- Claude

## Changelog

### Version 1.0.0 (Initial Release)
- ✅ OAuth client secret auditing
- ✅ Certificate auditing (Sign and Verify)
- ✅ SAML signing certificate auditing
- ✅ CSV export functionality
- ✅ HTML export with professional styling
- ✅ Color-coded console output
- ✅ Summary statistics
- ✅ Sorting by expiration date
- ✅ Status categorization (EXPIRED, CRITICAL, WARNING, OK)

## Support

For issues, questions, or suggestions:
- 🐛 [Open an issue](https://github.com/domkirby/Maybe-Helpful-MSFT-Scripts/issues)
---

**⭐ If you find this script helpful, please consider giving it a star on GitHub!**