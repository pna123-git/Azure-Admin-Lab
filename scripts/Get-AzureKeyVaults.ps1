#Requires -Modules Az.Accounts, Az.KeyVault

<#
.SYNOPSIS
    Lists Azure Key Vaults in the current or specified subscription.
.DESCRIPTION
    Type: Security / audit — answers "where are our Key Vaults and how are they configured?"
.PARAMETER SubscriptionId
    Optional subscription ID. Switches context before listing Key Vaults.
#>

param(
    [Parameter()]
    [string]$SubscriptionId
)

# Ensure we are signed in to Azure before running Key Vault commands
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Connect-AzAccount
    $context = Get-AzContext
}

# Switch to a specific subscription when -SubscriptionId is provided
if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    $context = Get-AzContext
}

# Confirm which subscription is being audited
Write-Host "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))`n" -ForegroundColor Cyan

# Get all Key Vaults in the active subscription
$keyVaults = Get-AzKeyVault

if (-not $keyVaults) {
    Write-Warning "No Key Vaults found in this subscription."
    exit 0
}

# Show vault location and key security settings for a quick compliance review
$keyVaults |
    Select-Object VaultName, ResourceGroupName, Location, @{
        Name = 'Sku'
        Expression = { $_.Sku }
    },
    EnableRbacAuthorization,   # True = RBAC model; False = legacy access policies
    EnablePurgeProtection,       # Prevents permanent deletion before retention expires
    EnableSoftDelete |           # Keeps deleted vaults/objects recoverable for a period
    Format-Table -AutoSize
