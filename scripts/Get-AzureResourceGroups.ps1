#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Lists resource groups in the current or specified Azure subscription.
.DESCRIPTION
    Type: Inventory / discovery — answers "what resource groups exist in this subscription?"
.PARAMETER SubscriptionId
    Optional subscription ID. Switches context before listing resource groups.
#>

param(
    [Parameter()]
    [string]$SubscriptionId
)

# Ensure we are signed in to Azure before running resource commands
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

# Confirm which subscription is being queried (helps avoid working in the wrong environment)
Write-Host "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))`n" -ForegroundColor Cyan

# Get all resource groups in the active subscription
$resourceGroups = Get-AzResourceGroup

if (-not $resourceGroups) {
    Write-Warning "No resource groups found in this subscription."
    exit 0
}

# Show name, region, deployment state, and tags for each resource group
$resourceGroups |
    Select-Object ResourceGroupName, Location, ProvisioningState, Tags |
    Format-Table -AutoSize
