#requires -Version 7.0
Set-StrictMode -Version Latest

function Parse-TracerouteSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    $lines = Get-Content -Path $Path -ErrorAction Stop
    $hops = @()
    foreach ($l in $lines) {
        if ($l -match '^\s*(\d+)\s+([^\s]+)\s+(\d+\.\d+)\s*ms') {
            $hops += [pscustomobject]@{ Hop=[int]$Matches[1]; Host=$Matches[2]; RTTms=[double]$Matches[3] }
        }
    }
    return $hops
}

function Compare-TracerouteHops {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Old,
        [Parameter(Mandatory)]
        [object[]]$New
    )
    $maxHop = [math]::Max(($Old | Measure-Object Hop -Maximum).Maximum, ($New | Measure-Object Hop -Maximum).Maximum)
    $diffs = @()
    for ($i=1; $i -le $maxHop; $i++) {
        $o = $Old | Where-Object { $_.Hop -eq $i } | Select-Object -First 1
        $n = $New | Where-Object { $_.Hop -eq $i } | Select-Object -First 1
        $diffs += [pscustomobject]@{
            Hop = $i
            OldHost = $o?.Host
            NewHost = $n?.Host
            HostChanged = ($o -and $n) ? ($o.Host -ne $n.Host) : $true
            OldRTTms = $o?.RTTms
            NewRTTms = $n?.RTTms
            RTTDeltaMs = ($o -and $n) ? ([math]::Round(($n.RTTms - $o.RTTms),2)) : $null
        }
    }
    return $diffs
}

Export-ModuleMember -Function Parse-TracerouteSnapshot, Compare-TracerouteHops
