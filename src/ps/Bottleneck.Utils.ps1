# Bottleneck.Utils.ps1
# Utility functions, constants, and helpers

# ========== Constants ==========
$BottleneckCategories = @('Storage','Power','Startup','Network','Update','Driver','Browser')

# ========== Result Creation ==========
function New-BottleneckResult {
    param(
        [string]$Id,
        [string]$Tier,
        [string]$Category,
        [int]$Impact,
        [int]$Confidence,
        [int]$Effort,
        [int]$Priority,
        [string]$Evidence,
        [string]$FixId,
        [string]$Message
    )
    [PSCustomObject]@{
        Id = $Id
        Tier = $Tier
        Category = $Category
        Impact = $Impact
        Confidence = $Confidence
        Effort = $Effort
        Priority = $Priority
        Evidence = $Evidence
        FixId = $FixId
        Message = $Message
        Score = [math]::Round(($Impact * $Confidence) / ($Effort + 1),2)
    }
}

function Get-SafeWinEvent {
    <#
    .SYNOPSIS
    Safely retrieves Windows Event Log entries with robust error handling.

    .DESCRIPTION
    Wrapper around Get-WinEvent that handles common error scenarios:
    - Null or invalid StartTime values
    - Access denied errors
    - Log not found errors
    - Timeout protection

    .PARAMETER FilterHashtable
    The filter hashtable to pass to Get-WinEvent

    .PARAMETER MaxEvents
    Maximum number of events to retrieve

    .PARAMETER TimeoutSeconds
    Timeout for the query (default: 10 seconds)
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$FilterHashtable,

        [ValidateRange(1, 1000)]
        [int]$MaxEvents = 100,

        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 10
    )

    try {
        # Validate and clean StartTime if present
        if ($FilterHashtable.ContainsKey('StartTime')) {
            $startTime = $FilterHashtable['StartTime']

            # Handle null or invalid datetime
            if ($null -eq $startTime -or $startTime -eq [datetime]::MinValue) {
                # Default to 7 days ago
                $FilterHashtable['StartTime'] = (Get-Date).AddDays(-7)
            }
            elseif ($startTime -is [string]) {
                # Try to parse string to datetime
                try {
                    $FilterHashtable['StartTime'] = [datetime]::Parse($startTime)
                } catch {
                    $FilterHashtable['StartTime'] = (Get-Date).AddDays(-7)
                }
            }
            elseif ($startTime -gt (Get-Date)) {
                # Future date, use 7 days ago instead
                $FilterHashtable['StartTime'] = (Get-Date).AddDays(-7)
            }
        }

        # Use Invoke-WithTimeout if available, otherwise direct call
        if (Get-Command Invoke-WithTimeout -ErrorAction SilentlyContinue) {
            return Invoke-WithTimeout -TimeoutSeconds $TimeoutSeconds -ScriptBlock {
                Get-WinEvent -FilterHashtable $using:FilterHashtable -MaxEvents $using:MaxEvents -ErrorAction SilentlyContinue
            }
        }
        else {
            return Get-WinEvent -FilterHashtable $FilterHashtable -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-BottleneckLog "Access denied to event log: $($FilterHashtable.LogName)" -Level "WARN"
        return @()
    }
    catch [System.Diagnostics.Eventing.Reader.EventLogNotFoundException] {
        Write-BottleneckLog "Event log not found: $($FilterHashtable.LogName)" -Level "WARN"
        return @()
    }
    catch [System.Exception] {
        Write-BottleneckLog "Error querying event log: $($_.Exception.Message)" -Level "WARN"
        return @()
    }
}
