<#
.SYNOPSIS
    Audits Entra ID Enterprise Applications for expiring credentials.

.DESCRIPTION
    This script connects to Microsoft Graph and retrieves all enterprise applications,
    then audits their OAuth client secrets, certificates, and SAML signing certificates
    for expiration dates. It prioritizes credentials expiring soon and highlights those
    expiring within 60 days.

.PARAMETER TenantId
    The Entra ID tenant ID to connect to. If not specified, uses the default tenant.

.PARAMETER ExportPath
    Optional path to export the results. The script will create both CSV and HTML files.
    Specify without extension (e.g., "C:\Reports\AppCredentials")

.EXAMPLE
    .\Audit-EntraIDAppCredentials.ps1
    
.EXAMPLE
    .\Audit-EntraIDAppCredentials.ps1 -TenantId "your-tenant-id" -ExportPath "C:\Reports\AppCredentials"

.NOTES
    Requires: Microsoft.Graph.Applications module
    Minimum required scope: Application.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $false)]
    [string]$ExportPath
)

#Requires -Modules Microsoft.Graph.Applications

function Get-DaysUntilExpiry {
    param([datetime]$ExpiryDate)
    return [math]::Round(($ExpiryDate - (Get-Date)).TotalDays)
}

function Get-ExpiryStatus {
    param([int]$DaysUntilExpiry)
    
    if ($DaysUntilExpiry -lt 0) { return "EXPIRED" }
    elseif ($DaysUntilExpiry -le 30) { return "CRITICAL" }
    elseif ($DaysUntilExpiry -le 60) { return "WARNING" }
    else { return "OK" }
}

# Connect to Microsoft Graph with minimal required permissions
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

$connectParams = @{
    Scopes = @("Application.Read.All")
}

if ($TenantId) {
    $connectParams.TenantId = $TenantId
}

try {
    Connect-MgGraph @connectParams -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

# Get the current context
$context = Get-MgContext
Write-Host "Connected to tenant: $($context.TenantId)" -ForegroundColor Green
Write-Host "`nRetrieving enterprise applications..." -ForegroundColor Cyan

# Retrieve all applications
try {
    $applications = Get-MgApplication -All -Property "Id,AppId,DisplayName,PasswordCredentials,KeyCredentials"
    Write-Host "Found $($applications.Count) applications" -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve applications: $_"
    Disconnect-MgGraph
    exit 1
}

# Also get service principals for SAML certificate information
Write-Host "Retrieving service principals for SAML certificate data..." -ForegroundColor Cyan
try {
    $servicePrincipals = Get-MgServicePrincipal -All -Property "Id,AppId,DisplayName,PreferredTokenSigningKeyThumbprint,KeyCredentials"
    Write-Host "Found $($servicePrincipals.Count) service principals" -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve service principals: $_"
    Disconnect-MgGraph
    exit 1
}

$results = @()

Write-Host "`nAnalyzing credentials..." -ForegroundColor Cyan

foreach ($app in $applications) {
    # Process Password Credentials (Client Secrets)
    foreach ($secret in $app.PasswordCredentials) {
        if ($secret.EndDateTime) {
            $daysUntilExpiry = Get-DaysUntilExpiry -ExpiryDate $secret.EndDateTime
            $status = Get-ExpiryStatus -DaysUntilExpiry $daysUntilExpiry
            
            $results += [PSCustomObject]@{
                ApplicationName = $app.DisplayName
                ApplicationId = $app.AppId
                ObjectId = $app.Id
                CredentialType = "Client Secret"
                CredentialId = $secret.KeyId
                DisplayName = $secret.DisplayName
                StartDate = $secret.StartDateTime
                ExpiryDate = $secret.EndDateTime
                DaysUntilExpiry = $daysUntilExpiry
                Status = $status
            }
        }
    }
    
    # Process Key Credentials (Certificates)
    foreach ($cert in $app.KeyCredentials) {
        if ($cert.EndDateTime) {
            $daysUntilExpiry = Get-DaysUntilExpiry -ExpiryDate $cert.EndDateTime
            $status = Get-ExpiryStatus -DaysUntilExpiry $daysUntilExpiry
            
            $certType = switch ($cert.Usage) {
                "Verify" { "Certificate (Verify)" }
                "Sign" { "Certificate (Sign)" }
                default { "Certificate" }
            }
            
            $results += [PSCustomObject]@{
                ApplicationName = $app.DisplayName
                ApplicationId = $app.AppId
                ObjectId = $app.Id
                CredentialType = $certType
                CredentialId = $cert.KeyId
                DisplayName = $cert.DisplayName
                StartDate = $cert.StartDateTime
                ExpiryDate = $cert.EndDateTime
                DaysUntilExpiry = $daysUntilExpiry
                Status = $status
            }
        }
    }
}

# Process SAML signing certificates from service principals
foreach ($sp in $servicePrincipals) {
    foreach ($cert in $sp.KeyCredentials) {
        if ($cert.EndDateTime -and $cert.Usage -eq "Sign") {
            $daysUntilExpiry = Get-DaysUntilExpiry -ExpiryDate $cert.EndDateTime
            $status = Get-ExpiryStatus -DaysUntilExpiry $daysUntilExpiry
            
            # Find matching application
            $matchingApp = $applications | Where-Object { $_.AppId -eq $sp.AppId }
            
            $results += [PSCustomObject]@{
                ApplicationName = $sp.DisplayName
                ApplicationId = $sp.AppId
                ObjectId = $sp.Id
                CredentialType = "SAML Signing Certificate"
                CredentialId = $cert.KeyId
                DisplayName = $cert.DisplayName
                StartDate = $cert.StartDateTime
                ExpiryDate = $cert.EndDateTime
                DaysUntilExpiry = $daysUntilExpiry
                Status = $status
            }
        }
    }
}

# Sort by expiry date (soonest first)
$results = $results | Sort-Object ExpiryDate

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "ENTRA ID APPLICATION CREDENTIALS AUDIT REPORT" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan
Write-Host "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Tenant: $($context.TenantId)" -ForegroundColor Gray
Write-Host "Total Credentials Found: $($results.Count)`n" -ForegroundColor Gray

# Display summary statistics
$expiredCount = ($results | Where-Object { $_.Status -eq "EXPIRED" }).Count
$criticalCount = ($results | Where-Object { $_.Status -eq "CRITICAL" }).Count
$warningCount = ($results | Where-Object { $_.Status -eq "WARNING" }).Count

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  EXPIRED (< 0 days):          $expiredCount" -ForegroundColor Red
Write-Host "  CRITICAL (0-30 days):        $criticalCount" -ForegroundColor Red
Write-Host "  WARNING (31-60 days):        $warningCount" -ForegroundColor Yellow
Write-Host "  OK (> 60 days):              $($results.Count - $expiredCount - $criticalCount - $warningCount)" -ForegroundColor Green
Write-Host ""

# Display credentials expiring within 60 days with highlighting
$urgentCredentials = $results | Where-Object { $_.DaysUntilExpiry -le 60 }

if ($urgentCredentials.Count -gt 0) {
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "CREDENTIALS EXPIRING WITHIN 60 DAYS" -ForegroundColor Red
    Write-Host "============================================`n" -ForegroundColor Red
    
    foreach ($cred in $urgentCredentials) {
        $color = switch ($cred.Status) {
            "EXPIRED" { "Red" }
            "CRITICAL" { "Red" }
            "WARNING" { "Yellow" }
            default { "White" }
        }
        
        Write-Host "[$($cred.Status)]" -ForegroundColor $color -NoNewline
        Write-Host " $($cred.ApplicationName)" -ForegroundColor White
        Write-Host "  Type: $($cred.CredentialType)" -ForegroundColor Gray
        Write-Host "  Display Name: $($cred.DisplayName)" -ForegroundColor Gray
        Write-Host "  Expiry Date: $($cred.ExpiryDate.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
        Write-Host "  Days Until Expiry: $($cred.DaysUntilExpiry)" -ForegroundColor $color
        Write-Host "  Application ID: $($cred.ApplicationId)" -ForegroundColor Gray
        Write-Host ""
    }
}

# Display all credentials in a table format
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "ALL CREDENTIALS (Sorted by Expiry Date)" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

$results | Format-Table -Property @(
    @{Label="Application"; Expression={$_.ApplicationName}; Width=30},
    @{Label="Type"; Expression={$_.CredentialType}; Width=25},
    @{Label="Expiry Date"; Expression={$_.ExpiryDate.ToString('yyyy-MM-dd')}; Width=12},
    @{Label="Days"; Expression={$_.DaysUntilExpiry}; Width=6},
    @{Label="Status"; Expression={$_.Status}; Width=10}
) -AutoSize

# Export to CSV and HTML if requested
if ($ExportPath) {
    # Remove extension if provided
    $basePath = [System.IO.Path]::GetFileNameWithoutExtension($ExportPath)
    $directory = [System.IO.Path]::GetDirectoryName($ExportPath)
    if ([string]::IsNullOrEmpty($directory)) {
        $directory = Get-Location
    }
    $csvPath = Join-Path $directory "$basePath.csv"
    $htmlPath = Join-Path $directory "$basePath.html"
    
    # Export CSV
    try {
        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nCSV exported to: $csvPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to export CSV: $_"
    }
    
    # Generate HTML Report
    try {
        $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Entra ID Application Credentials Audit Report</title>
    <style>
        @media print {
            body {
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            .page-break {
                page-break-before: always;
            }
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            background-color: #f5f5f5;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background-color: white;
            padding: 40px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        
        h1 {
            color: #0078d4;
            border-bottom: 3px solid #0078d4;
            padding-bottom: 10px;
            margin-bottom: 20px;
            font-size: 28px;
        }
        
        h2 {
            color: #2c3e50;
            margin-top: 30px;
            margin-bottom: 15px;
            font-size: 22px;
            border-left: 4px solid #0078d4;
            padding-left: 10px;
        }
        
        .report-header {
            background-color: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 30px;
        }
        
        .report-header p {
            margin: 5px 0;
            color: #666;
        }
        
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        
        .summary-card {
            padding: 20px;
            border-radius: 8px;
            text-align: center;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .summary-card.expired {
            background-color: #dc3545;
            color: white;
        }
        
        .summary-card.critical {
            background-color: #fd7e14;
            color: white;
        }
        
        .summary-card.warning {
            background-color: #ffc107;
            color: #333;
        }
        
        .summary-card.ok {
            background-color: #28a745;
            color: white;
        }
        
        .summary-card .count {
            font-size: 36px;
            font-weight: bold;
            display: block;
            margin-bottom: 5px;
        }
        
        .summary-card .label {
            font-size: 14px;
            font-weight: 500;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 30px;
            font-size: 14px;
        }
        
        thead {
            background-color: #0078d4;
            color: white;
        }
        
        th {
            padding: 12px;
            text-align: left;
            font-weight: 600;
            position: sticky;
            top: 0;
        }
        
        td {
            padding: 10px 12px;
            border-bottom: 1px solid #ddd;
        }
        
        tbody tr:hover {
            background-color: #f8f9fa;
        }
        
        tbody tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        
        .status-badge {
            padding: 4px 12px;
            border-radius: 12px;
            font-weight: 600;
            font-size: 12px;
            display: inline-block;
            text-transform: uppercase;
        }
        
        .status-expired {
            background-color: #dc3545;
            color: white;
        }
        
        .status-critical {
            background-color: #fd7e14;
            color: white;
        }
        
        .status-warning {
            background-color: #ffc107;
            color: #333;
        }
        
        .status-ok {
            background-color: #28a745;
            color: white;
        }
        
        .days-cell {
            font-weight: 600;
        }
        
        .days-expired {
            color: #dc3545;
        }
        
        .days-critical {
            color: #fd7e14;
        }
        
        .days-warning {
            color: #856404;
        }
        
        .days-ok {
            color: #28a745;
        }
        
        .credential-type {
            font-size: 12px;
            color: #666;
            background-color: #e9ecef;
            padding: 3px 8px;
            border-radius: 4px;
            display: inline-block;
        }
        
        .app-name {
            font-weight: 600;
            color: #2c3e50;
        }
        
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            text-align: center;
            color: #666;
            font-size: 12px;
        }
        
        .alert-section {
            background-color: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin-bottom: 30px;
            border-radius: 4px;
        }
        
        .alert-section h3 {
            color: #856404;
            margin-bottom: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Entra ID Application Credentials Audit Report</h1>
        
        <div class="report-header">
            <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
            <p><strong>Tenant ID:</strong> $($context.TenantId)</p>
            <p><strong>Total Credentials:</strong> $($results.Count)</p>
            <p><strong>Applications Scanned:</strong> $($applications.Count)</p>
        </div>
        
        <h2>Summary Overview</h2>
        <div class="summary-grid">
            <div class="summary-card expired">
                <span class="count">$expiredCount</span>
                <span class="label">EXPIRED</span>
            </div>
            <div class="summary-card critical">
                <span class="count">$criticalCount</span>
                <span class="label">CRITICAL (0-30 days)</span>
            </div>
            <div class="summary-card warning">
                <span class="count">$warningCount</span>
                <span class="label">WARNING (31-60 days)</span>
            </div>
            <div class="summary-card ok">
                <span class="count">$($results.Count - $expiredCount - $criticalCount - $warningCount)</span>
                <span class="label">OK (&gt;60 days)</span>
            </div>
        </div>
"@

        # Add urgent credentials section if any exist
        if ($urgentCredentials.Count -gt 0) {
            $htmlContent += @"
        
        <div class="alert-section">
            <h3>⚠️ Immediate Attention Required</h3>
            <p>There are <strong>$($urgentCredentials.Count)</strong> credentials expiring within 60 days that require immediate attention.</p>
        </div>
        
        <h2>Credentials Expiring Within 60 Days</h2>
        <table>
            <thead>
                <tr>
                    <th>Application Name</th>
                    <th>Credential Type</th>
                    <th>Display Name</th>
                    <th>Expiry Date</th>
                    <th>Days Until Expiry</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
"@
            foreach ($cred in $urgentCredentials) {
                $statusClass = switch ($cred.Status) {
                    "EXPIRED" { "expired" }
                    "CRITICAL" { "critical" }
                    "WARNING" { "warning" }
                    default { "ok" }
                }
                
                $htmlContent += @"
                <tr>
                    <td class="app-name">$([System.Security.SecurityElement]::Escape($cred.ApplicationName))</td>
                    <td><span class="credential-type">$([System.Security.SecurityElement]::Escape($cred.CredentialType))</span></td>
                    <td>$([System.Security.SecurityElement]::Escape($cred.DisplayName))</td>
                    <td>$($cred.ExpiryDate.ToString('yyyy-MM-dd'))</td>
                    <td class="days-cell days-$statusClass">$($cred.DaysUntilExpiry)</td>
                    <td><span class="status-badge status-$statusClass">$($cred.Status)</span></td>
                </tr>
"@
            }
            
            $htmlContent += @"
            </tbody>
        </table>
"@
        }
        
        # Add all credentials section
        $htmlContent += @"
        
        <div class="page-break"></div>
        <h2>All Credentials (Sorted by Expiry Date)</h2>
        <table>
            <thead>
                <tr>
                    <th>Application Name</th>
                    <th>Credential Type</th>
                    <th>Display Name</th>
                    <th>Expiry Date</th>
                    <th>Days Until Expiry</th>
                    <th>Status</th>
                    <th>Application ID</th>
                </tr>
            </thead>
            <tbody>
"@
        
        foreach ($cred in $results) {
            $statusClass = switch ($cred.Status) {
                "EXPIRED" { "expired" }
                "CRITICAL" { "critical" }
                "WARNING" { "warning" }
                default { "ok" }
            }
            
            $htmlContent += @"
                <tr>
                    <td class="app-name">$([System.Security.SecurityElement]::Escape($cred.ApplicationName))</td>
                    <td><span class="credential-type">$([System.Security.SecurityElement]::Escape($cred.CredentialType))</span></td>
                    <td>$([System.Security.SecurityElement]::Escape($cred.DisplayName))</td>
                    <td>$($cred.ExpiryDate.ToString('yyyy-MM-dd'))</td>
                    <td class="days-cell days-$statusClass">$($cred.DaysUntilExpiry)</td>
                    <td><span class="status-badge status-$statusClass">$($cred.Status)</span></td>
                    <td style="font-size: 11px; color: #666;">$($cred.ApplicationId)</td>
                </tr>
"@
        }
        
        $htmlContent += @"
            </tbody>
        </table>
        
        <div class="footer">
            <p>This report was generated by the Entra ID Application Credentials Audit Script</p>
            <p>For questions or issues, please contact your IT administrator</p>
        </div>
    </div>
</body>
</html>
"@
        
        # Write HTML file
        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Host "HTML report exported to: $htmlPath" -ForegroundColor Green
        Write-Host "  → Open in browser and use 'Print to PDF' to create a PDF" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to export HTML: $_"
    }
}

# Disconnect from Microsoft Graph
Disconnect-MgGraph | Out-Null
Write-Host "`nDisconnected from Microsoft Graph" -ForegroundColor Cyan
Write-Host "`nAudit complete!" -ForegroundColor Green
