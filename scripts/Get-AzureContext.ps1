#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Shows the current Azure session and lists accessible tenants and subscriptions.
.DESCRIPTION
    Type: Context / identity — answers "who am I connected as?" and "which tenant owns each subscription?"
#>

# Reuse existing login if present; otherwise prompt for Azure credentials
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Connect-AzAccount
    $context = Get-AzContext
}

# Section 1: show the active account, tenant, and subscription used by PowerShell commands
Write-Host "`nCurrent session" -ForegroundColor Cyan
$context | Select-Object `
    @{ Name = 'Account'; Expression = { $_.Account.Id } },
    @{ Name = 'TenantId'; Expression = { $_.Tenant.Id } },
    @{ Name = 'SubscriptionName'; Expression = { $_.Subscription.Name } },
    @{ Name = 'SubscriptionId'; Expression = { $_.Subscription.Id } } |
    Format-List

# Section 2: list every Entra ID tenant this account can access (home + guest tenants)
$tenants = Get-AzTenant

# Build a lookup table so we can show a friendly tenant name next to each subscription
$tenantLookup = @{}
foreach ($tenant in $tenants) {
    $tenantLookup[$tenant.Id] = $tenant.DisplayName
}

Write-Host "Accessible tenants" -ForegroundColor Cyan
$tenants |
    Select-Object DisplayName, Id, @{
        Name = 'DefaultDomain'
        Expression = { ($_.Domains | Select-Object -First 1) }
    } |
    Format-Table -AutoSize

# Section 3: map each subscription to its owning tenant (useful with multiple tenants)
Write-Host "Subscriptions (with tenant)" -ForegroundColor Cyan
Get-AzSubscription |
    Select-Object Name, Id, TenantId, @{
        Name = 'TenantName'
        Expression = { $tenantLookup[$_.TenantId] }
    },
    State |
    Format-Table -AutoSize
