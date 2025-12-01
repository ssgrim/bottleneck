function Get-SafeWinEvent {
    param(
        [Parameter(Mandatory)][string] $LogName,
        [datetime] $StartTime,
        [int] $MaxEvents = 1000,
        [string] $ProviderName,
        [int] $Level
    )
    $filter = @{ LogName = $LogName }
    if ($StartTime) { $filter['StartTime'] = $StartTime }
    if ($ProviderName) { $filter['ProviderName'] = $ProviderName }
    if ($Level) { $filter['Level'] = $Level }
    try {
        return Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
    } catch {
        return @()
    }
}

Export-ModuleMember -Function Get-SafeWinEvent