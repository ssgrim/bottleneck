# Bottleneck.Logging.ps1
# Centralized logging framework

$script:LogPath = $null
$script:LogLevel = "INFO" # DEBUG, INFO, WARN, ERROR

function Initialize-BottleneckLogging {
    param(
        [Parameter()][ValidateNotNullOrEmpty()][string]$LogDirectory = "$PSScriptRoot\..\..\Reports"
    )

    # Prevent recursive initialization
    if ($script:LogPath) { return }

    if (!(Test-Path $LogDirectory)) {
        try {
            New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        } catch {}
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd'
    $script:LogPath = Join-Path $LogDirectory "bottleneck-$timestamp.log"

    # Write initial log entries directly to avoid recursion during initialization
    $initTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    try {
        "[$initTime] [INFO] === Bottleneck Diagnostic Session Started ===" | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
        "[$initTime] [INFO] Computer: $env:COMPUTERNAME" | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
        "[$initTime] [INFO] User: $env:USERNAME" | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
        "[$initTime] [INFO] PowerShell: $($PSVersionTable.PSVersion)" | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
    } catch {}
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

    # Only initialize if not already initialized (prevents recursion)
    if (-not $script:LogPath) {
        try {
            Initialize-BottleneckLogging -ErrorAction SilentlyContinue
        } catch {
            # If initialization fails, just write to console
            $script:LogPath = $null
        }
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
