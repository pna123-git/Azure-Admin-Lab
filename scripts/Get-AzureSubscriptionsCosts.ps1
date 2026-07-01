#Requires -Modules Az.Accounts

# =============================================================================
# EDIT THESE VALUES
# =============================================================================
$SubscriptionName = 'My Production Subscription'   # or leave empty
$SubscriptionId   = ''                             # e.g. 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# LastWeek | LastMonth | ThisMonth | Custom
$DatePreset       = 'LastMonth'

# Only when DatePreset = 'Custom' (yyyy-MM-dd)
$CustomStartDate  = '2026-06-01'
$CustomEndDate    = '2026-06-30'

# Leave empty for screen only, or set path e.g. '.\cost-report.csv'
$ExportPath       = ''
# =============================================================================

$today = (Get-Date).Date

switch ($DatePreset) {
    'LastWeek' {
        $rangeEnd   = $today.AddDays(-1)
        $rangeStart = $rangeEnd.AddDays(-6)
    }
    'LastMonth' {
        $firstOfThisMonth = Get-Date -Year $today.Year -Month $today.Month -Day 1
        $rangeEnd   = $firstOfThisMonth.AddDays(-1)
        $rangeStart = Get-Date -Year $rangeEnd.Year -Month $rangeEnd.Month -Day 1
    }
    'ThisMonth' {
        $rangeStart = Get-Date -Year $today.Year -Month $today.Month -Day 1
        $rangeEnd   = $today.AddDays(-1)
        if ($rangeEnd -lt $rangeStart) {
            Write-Error "ThisMonth has no completed days yet. Use Custom or wait until tomorrow."
            exit 1
        }
    }
    'Custom' {
        if (-not $CustomStartDate -or -not $CustomEndDate) {
            Write-Error "Custom requires CustomStartDate and CustomEndDate (yyyy-MM-dd)."
            exit 1
        }
        $rangeStart = [datetime]::ParseExact($CustomStartDate, 'yyyy-MM-dd', $null)
        $rangeEnd   = [datetime]::ParseExact($CustomEndDate, 'yyyy-MM-dd', $null)
    }
    default {
        Write-Error "DatePreset must be LastWeek, LastMonth, ThisMonth, or Custom."
        exit 1
    }
}

if ($rangeStart -gt $rangeEnd) {
    Write-Error "Start date must be on or before end date."
    exit 1
}

$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Connect-AzAccount
}

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}
elseif ($SubscriptionName) {
    $sub = Get-AzSubscription | Where-Object Name -eq $SubscriptionName
    if (-not $sub) {
        Write-Error "Subscription not found: '$SubscriptionName'"
        exit 1
    }
    if (@($sub).Count -gt 1) {
        Write-Error "Multiple subscriptions named '$SubscriptionName'. Use SubscriptionId instead."
        exit 1
    }
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
}
else {
    Write-Error "Set SubscriptionName or SubscriptionId at the top of this script."
    exit 1
}

$context    = Get-AzContext
$subId      = $context.Subscription.Id
$subName    = $context.Subscription.Name
$startLabel = $rangeStart.ToString('yyyy-MM-dd')
$endLabel   = $rangeEnd.ToString('yyyy-MM-dd')

Write-Host "`nAzure subscription cost report" -ForegroundColor Cyan
Write-Host "Subscription : $subName ($subId)"
Write-Host "Date range   : $startLabel to $endLabel ($DatePreset)`n"

$uri = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.CostManagement/query?api-version=2023-11-01"

$body = @{
    type       = 'ActualCost'
    timeframe  = 'Custom'
    timePeriod = @{
        from = $startLabel
        to   = $endLabel
    }
    dataset = @{
        granularity = 'None'
        aggregation = @{
            totalCost = @{
                name     = 'PreTaxCost'
                function = 'Sum'
            }
        }
        grouping = @(
            @{ type = 'Dimension'; name = 'ResourceId' }
            @{ type = 'Dimension'; name = 'ResourceGroupName' }
            @{ type = 'Dimension'; name = 'ResourceType' }
            @{ type = 'Dimension'; name = 'ResourceLocation' }
        )
    }
} | ConvertTo-Json -Depth 10 -Compress

$allRows  = [System.Collections.Generic.List[object]]::new()
$columns  = $null
$nextLink = $null

do {
    if ($nextLink) {
        $response = Invoke-AzRestMethod -Method GET -Uri $nextLink
    }
    else {
        $response = Invoke-AzRestMethod -Method POST -Uri $uri -Payload $body
    }

    if ($response.StatusCode -ge 400) {
        $err = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
        $msg = if ($err.error.message) { $err.error.message } else { $response.Content }
        Write-Error "Cost query failed: $msg"
        exit 1
    }

    $result = $response.Content | ConvertFrom-Json
    if (-not $columns) { $columns = $result.properties.columns }

    foreach ($row in $result.properties.rows) {
        $allRows.Add($row)
    }

    $nextLink = $result.properties.nextLink
} while ($nextLink)

if ($allRows.Count -eq 0) {
    Write-Warning "No cost data for this subscription and date range."
    exit 0
}

$names  = $columns | ForEach-Object { $_.name }
$report = [System.Collections.Generic.List[object]]::new()

foreach ($row in $allRows) {
    $item = @{}
    for ($i = 0; $i -lt $names.Count; $i++) {
        $item[$names[$i]] = $row[$i]
    }

    $resourceId = [string]$item['ResourceId']
    $cost       = [math]::Round([decimal]$item['PreTaxCost'], 2)
    if ($cost -eq 0) { continue }

    $report.Add([PSCustomObject]@{
        ResourceGroup = $item['ResourceGroupName']
        ResourceName  = if ($resourceId) { ($resourceId -split '/')[-1] } else { '' }
        ResourceType  = $item['ResourceType']
        Location      = $item['ResourceLocation']
        Cost          = $cost
        Currency      = if ($item['Currency']) { $item['Currency'] } else { 'USD' }
        ResourceId    = $resourceId
    })
}

$report = $report | Sort-Object Cost -Descending

if (-not $report) {
    Write-Warning "All rows had zero cost for this period."
    exit 0
}

$total    = ($report | Measure-Object -Property Cost -Sum).Sum
$currency = ($report | Select-Object -First 1).Currency

$report | Select-Object ResourceGroup, ResourceName, ResourceType, Location, Cost, Currency | Format-Table -AutoSize

Write-Host "Summary" -ForegroundColor Cyan
Write-Host "Resources with cost : $($report.Count)"
Write-Host "Total cost          : $([math]::Round($total, 2)) $currency"
Write-Host "Period              : $startLabel to $endLabel`n"

if ($ExportPath) {
    $report | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Host "Exported to: $ExportPath" -ForegroundColor Green
}