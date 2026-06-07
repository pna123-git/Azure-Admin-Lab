#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Connects to Azure and lists all subscriptions with name and ID.
.DESCRIPTION
    Type: Discovery — lists every subscription the signed-in account can access.
#>

# Check for an existing Azure login session (avoids prompting if already connected)
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    # No active session — open browser sign-in and create a new context
    Connect-AzAccount
}

# Retrieve all subscriptions visible to the current account in the active tenant
$subscriptions = Get-AzSubscription

if (-not $subscriptions) {
    Write-Warning "No subscriptions found for the current account."
    exit 1
}

# Display subscription friendly name and GUID for easy copy/paste into other commands
$subscriptions |
    Select-Object Name, Id |
    Format-Table -AutoSize
