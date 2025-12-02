function Analyze-WiresharkCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $Path,
        [ValidateSet('csv','json')]
        [string] $Format = 'csv'
    )
    if (-not (Test-Path $Path)) { throw "Wireshark file not found: $Path" }
    $summary = [ordered]@{ Packets=0; Drops=0; AvgLatencyMs=0; MaxLatencyMs=0; MinLatencyMs=0 }
    switch ($Format) {
        'csv' {
            $rows = Import-Csv -Path $Path
            if (-not $rows) { return ($summary | ConvertTo-Json | ConvertFrom-Json) }
            $summary.Packets = $rows.Count
            # Expect columns like: Time,Source,Destination,Protocol,Length,Info,Delta
            $latencies = @()
            foreach ($r in $rows) {
                if ($r.Delta -and ($r.Delta -as [double])) { $latencies += [double]$r.Delta }
                if ($r.Info -match 'Retransmission|Dup ACK|Out-of-order') { $summary.Drops++ }
            }
            if ($latencies.Count -gt 0) {
                $summary.AvgLatencyMs = [math]::Round((($latencies | Measure-Object -Average).Average) * 1000, 2)
                $summary.MaxLatencyMs = [math]::Round(((($latencies | Measure-Object -Maximum).Maximum) * 1000), 2)
                $summary.MinLatencyMs = [math]::Round(((($latencies | Measure-Object -Minimum).Minimum) * 1000), 2)
            }
        }
        'json' {
            $obj = Get-Content -Path $Path -Raw | ConvertFrom-Json
            if ($obj -is [array]) { $summary.Packets = $obj.Count }
            # Heuristic placeholders
        }
    }
    return ($summary | ConvertTo-Json | ConvertFrom-Json)
}

function Add-WiresharkSummaryToReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Summary
    )
    try {
        New-WiresharkSection -Summary $Summary
    } catch {
        # Fallback: write to host
        Write-Host ("Wireshark: packets={0}, drops={1}, avg={2}ms, max={3}ms" -f $Summary.Packets, $Summary.Drops, $Summary.AvgLatencyMs, $Summary.MaxLatencyMs)
    }
}
