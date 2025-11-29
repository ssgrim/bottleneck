# Bottleneck.Utils.ps1
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
