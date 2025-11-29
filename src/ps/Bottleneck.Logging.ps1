# Bottleneck.Logging.ps1
# Centralized logging framework

$script:LogPath = $null
$script:LogLevel = "INFO" # DEBUG, INFO, WARN, ERROR

function Initialize-BottleneckLogging {
    param(
        [Parameter()][string]$LogDirectory = "$PSScriptRoot\..\..\Reports"
    )
    
    if (!(Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd'
    $script:LogPath = Join-Path $LogDirectory "bottleneck-$timestamp.log"
    
    Write-BottleneckLog "=== Bottleneck Diagnostic Session Started ===" -Level "INFO"
    Write-BottleneckLog "Computer: $env:COMPUTERNAME" -Level "INFO"
    Write-BottleneckLog "User: $env:USERNAME" -Level "INFO"
    Write-BottleneckLog "PowerShell: $($PSVersionTable.PSVersion)" -Level "INFO"
}

function Write-BottleneckLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",
        
        [Parameter()]
        [string]$CheckId = ""
    )
    
    if (-not $script:LogPath) {
        Initialize-BottleneckLogging
    }
    
    # Skip DEBUG messages unless log level is DEBUG
    if ($Level -eq "DEBUG" -and $script:LogLevel -ne "DEBUG") {
        return
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level]"
    
    if ($CheckId) {
        $logEntry += " [$CheckId]"
    }
    
    $logEntry += " $Message"
    
    try {
        $logEntry | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
    } catch {
        # Fallback: write to console if logging fails
        Write-Verbose $logEntry
    }
    
    # Also write warnings and errors to console
    switch ($Level) {
        "WARN" { Write-Warning $Message }
        "ERROR" { Write-Error $Message }
    }
}

function Get-BottleneckLogPath {
    return $script:LogPath
}

function Set-BottleneckLogLevel {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")]
        [string]$Level
    )
    $script:LogLevel = $Level
    Write-BottleneckLog "Log level set to: $Level" -Level "INFO"
}
