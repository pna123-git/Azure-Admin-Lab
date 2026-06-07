#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Connects to Azure and lists all subscriptions with name and ID.
#>

$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Connect-AzAccount
}

$subscriptions = Get-AzSubscription

if (-not $subscriptions) {
    Write-Warning "No subscriptions found for the current account."
    exit 1
}

$subscriptions |
    Select-Object Name, Id |
    Format-Table -AutoSize
