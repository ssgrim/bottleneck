
# Bottleneck.Report.ps1
function Invoke-BottleneckReport {
    param(
        [Parameter(Mandatory)]$Results,
        [Parameter()][ValidateSet('Quick','Standard','Deep')][string]$Tier = 'Quick',
        [Parameter()][ValidateNotNullOrEmpty()][string]$ReportsPath = "$PSScriptRoot/../../Reports"
    )
    . $PSScriptRoot/Bottleneck.ReportUtils.ps1
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $dateFolder = Get-Date -Format 'yyyy-MM-dd'
    $datePath = Join-Path $ReportsPath $dateFolder
    if (-not (Test-Path $datePath)) { New-Item -ItemType Directory -Path $datePath -Force | Out-Null }
    switch ($Tier) {
        'Quick' { $prefix = 'Basic-scan' }
        'Standard' { $prefix = 'Standard-scan' }
        'Deep' { $prefix = 'Full-scan' }
        default { $prefix = 'Scan' }
    }
    $htmlPath = Join-Path $datePath "$prefix-$timestamp.html"
    # Also save to user's Documents\ScanReports
    $userDocs = [Environment]::GetFolderPath('MyDocuments')
    $userScanDir = Join-Path $userDocs 'ScanReports'
    if (!(Test-Path $userScanDir)) { New-Item -Path $userScanDir -ItemType Directory | Out-Null }
    $userHtmlPath = Join-Path $userScanDir ([System.IO.Path]::GetFileName($htmlPath))
    # Also save to user's OneDrive Documents folder (check multiple possible locations)
    $oneDriveHtmlPath = $null
    $oneDrivePaths = @(
        "$env:OneDrive\Documents",
        "$env:OneDriveConsumer\Documents",
        "$env:OneDriveCommercial\Documents",
        "$env:USERPROFILE\OneDrive\Documents",
        "$env:USERPROFILE\OneDrive - Personal\Documents"
    )
    foreach ($path in $oneDrivePaths) {
        if ($path -and (Test-Path $path)) {
            $oneDriveHtmlPath = Join-Path $path ([System.IO.Path]::GetFileName($htmlPath))
            break
        }
    }
    $prev = Get-BottleneckPreviousScan -ReportsPath $ReportsPath
    $eventSummary = Get-BottleneckEventLogSummary -Days 7
    # Try to compute network fused alert level from recent monitor CSV
    $fusedAlert = $null
    try {
        $rca = Invoke-BottleneckNetworkRootCause -DisableProbes -DisableTraceroute
        if ($rca -and $rca.FusedAlertLevel) { $fusedAlert = $rca.FusedAlertLevel }
    }
    catch { }
    $html = @"
<html>
<head>
<title>Bottleneck Performance Analysis Report</title>
<meta charset="UTF-8">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    padding: 40px 20px;
    color: #333;
}
.container {
    max-width: 1200px;
    margin: 0 auto;
    background: #fff;
    border-radius: 12px;
    box-shadow: 0 10px 40px rgba(0,0,0,0.15);
    overflow: hidden;
}
.header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 40px;
    text-align: center;
}
.header h1 {
    font-size: 32px;
    margin-bottom: 10px;
    font-weight: 300;
    letter-spacing: 1px;
}
.header .subtitle {
    font-size: 14px;
    opacity: 0.9;
    text-transform: uppercase;
    letter-spacing: 2px;
}
.meta {
    background: #f8f9fa;
    padding: 20px 40px;
    border-bottom: 1px solid #e9ecef;
    display: flex;
    justify-content: space-between;
    flex-wrap: wrap;
}
.meta-item {
    margin: 5px 0;
}
.meta-label {
    font-size: 11px;
    color: #6c757d;
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-right: 8px;
}
.meta-value {
    font-weight: 600;
    color: #495057;
}
.content { padding: 40px; }
.section {
    margin-bottom: 40px;
}
.section h2 {
    font-size: 20px;
    color: #495057;
    margin-bottom: 20px;
    padding-bottom: 10px;
    border-bottom: 2px solid #667eea;
    font-weight: 600;
}
.metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 20px;
    margin-bottom: 30px;
}
.metric-card {
    background: #f8f9fa;
    padding: 20px;
    border-radius: 8px;
    border-left: 4px solid #667eea;
}
.metric-label {
    font-size: 12px;
    color: #6c757d;
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-bottom: 8px;
}
.metric-value {
    font-size: 28px;
    font-weight: 700;
    color: #495057;
}
table {
    border-collapse: collapse;
    width: 100%;
    margin-bottom: 24px;
    font-size: 14px;
    background: white;
    border-radius: 8px;
    overflow: hidden;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
}
th {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 16px;
    text-align: left;
    font-weight: 600;
    text-transform: uppercase;
    font-size: 11px;
    letter-spacing: 1px;
}
td {
    border-bottom: 1px solid #e9ecef;
    padding: 16px;
}
tr:hover {
    background: #f8f9fa;
    transition: background 0.2s;
}
button {
    padding: 8px 16px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 12px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    transition: transform 0.2s, box-shadow 0.2s;
}
button:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(102,126,234,0.4);
}
.trend-up {
    color: #28a745;
    font-weight: bold;
    font-size: 18px;
}
.trend-down {
    color: #dc3545;
    font-weight: bold;
    font-size: 18px;
}
.badge {
    display: inline-block;
    padding: 4px 12px;
    border-radius: 12px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}
.badge-success { background: #d4edda; color: #155724; }
.badge-warning { background: #fff3cd; color: #856404; }
.badge-danger { background: #f8d7da; color: #721c24; }
.badge-info { background: #d1ecf1; color: #0c5460; }
.score-green { background: #28a745; color: white; padding: 6px 12px; border-radius: 4px; font-weight: bold; }
.score-yellow { background: #ffc107; color: #333; padding: 6px 12px; border-radius: 4px; font-weight: bold; }
.score-orange { background: #fd7e14; color: white; padding: 6px 12px; border-radius: 4px; font-weight: bold; }
.score-red { background: #dc3545; color: white; padding: 6px 12px; border-radius: 4px; font-weight: bold; }
ul { list-style: none; padding: 0; }
ul li {
    padding: 12px;
    margin: 8px 0;
    background: #f8f9fa;
    border-radius: 4px;
    border-left: 3px solid #667eea;
    font-size: 13px;
    line-height: 1.6;
}
.footer {
    background: #f8f9fa;
    padding: 20px 40px;
    text-align: center;
    font-size: 12px;
    color: #6c757d;
    border-top: 1px solid #e9ecef;
}
.ai-help-btn {
    padding: 6px 12px;
    background: linear-gradient(135deg, #00d4ff 0%, #0099ff 100%);
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-left: 8px;
    transition: all 0.3s;
}
.ai-help-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(0, 153, 255, 0.4);
}
.ai-help-btn::before {
    content: '🤖 ';
}
</style>
</head>
<body>
<script>
function getAIHelp(checkId, evidence, message, provider) {
    const systemInfo = 'Computer: $env:COMPUTERNAME, OS: Windows';
    const prompt = 'I am troubleshooting a performance issue on my Windows computer.\n\nIssue: '+checkId+'\nDescription: '+message+'\nEvidence: '+evidence+'\nSystem: '+systemInfo+'\n\nPlease provide:\n1. Root cause analysis\n2. Step-by-step troubleshooting steps\n3. Recommended fixes (prioritized)\n4. Prevention tips';

    let searchUrl;
    if (provider === 'chatgpt') {
        searchUrl = 'https://chat.openai.com/?q='+encodeURIComponent(prompt);
    } else if (provider === 'copilot') {
        searchUrl = 'https://copilot.microsoft.com/?q='+encodeURIComponent(prompt);
    } else if (provider === 'gemini') {
        searchUrl = 'https://gemini.google.com/app?q='+encodeURIComponent(prompt);
    } else {
        searchUrl = 'https://www.google.com/search?q='+encodeURIComponent(prompt);
    }
    window.open(searchUrl, '_blank');
}

function openWindowsSetting(settingPath) {
    const link = document.createElement('a');
    link.href = settingPath;
    link.target = '_blank';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}

function runFix(fixType) {
    const fixActions = {
        'Cleanup': {
            title: 'Disk Cleanup',
            description: 'This will open Windows Disk Cleanup utility.',
            action: () => openWindowsSetting('ms-settings:storagesense')
        },
        'Retrim': {
            title: 'SSD Optimization',
            description: 'This will open the Optimize Drives utility.',
            action: () => openWindowsSetting('ms-settings:deviceperformance')
        },
        'PowerPlanHighPerformance': {
            title: 'Power Plan',
            description: 'This will open Power Options to change to High Performance mode.',
            action: () => openWindowsSetting('ms-settings:powersleep')
        },
        'TriggerUpdate': {
            title: 'Windows Update',
            description: 'This will open Windows Update settings.',
            action: () => openWindowsSetting('ms-settings:windowsupdate')
        },
        'Defragment': {
            title: 'Defragment Drive',
            description: 'This will open the Optimize Drives utility.',
            action: () => openWindowsSetting('ms-settings:deviceperformance')
        },
        'MemoryDiagnostic': {
            title: 'Memory Diagnostic',
            description: 'To run Windows Memory Diagnostic, press Win+R and type: mdsched.exe',
            action: () => alert('To run Windows Memory Diagnostic:\\n1. Press Win+R\\n2. Type: mdsched.exe\\n3. Press Enter\\n4. Choose \\'Restart now and check for problems\\'')
        },
        'RestartServices': {
            title: 'Services Management',
            description: 'This will open the Services management console.',
            action: () => openWindowsSetting('ms-settings:appsfeatures')
        },
        'HighCPUProcess': {
            title: 'Task Manager',
            description: 'Opening Task Manager to manage processes.',
            action: () => alert('To open Task Manager:\\n1. Press Ctrl+Shift+Esc\\nOR\\n2. Right-click taskbar and select Task Manager\\n\\nClose high-CPU processes from the Processes tab.')
        },
        'HighMemoryUsage': {
            title: 'Task Manager',
            description: 'Opening Task Manager to manage memory.',
            action: () => alert('To open Task Manager:\\n1. Press Ctrl+Shift+Esc\\nOR\\n2. Right-click taskbar and select Task Manager\\n\\nSort by Memory column to find heavy users.')
        },
        'FanIssue': {
            title: 'Fan Issue Alert',
            description: 'Manual fan inspection required.',
            action: () => alert('⚠️ COOLING SYSTEM CHECK REQUIRED\\n\\n1. Shut down the computer\\n2. Unplug power cable\\n3. Open case and inspect fans\\n4. Clean dust from vents and fans\\n5. Ensure all fans spin freely\\n6. Replace failed fans\\n\\nIf laptop: Use compressed air to clean vents while off.')
        },
        'HighTemperature': {
            title: 'Critical Temperature Alert',
            description: 'CRITICAL: Immediate cooling system check needed!',
            action: () => alert('🔥 CRITICAL TEMPERATURE WARNING\\n\\nIMMEDIATE ACTIONS REQUIRED:\\n1. Save work and shut down NOW\\n2. Let system cool for 30 minutes\\n3. Clean all vents and fans\\n4. Check if fans are working\\n5. Reapply thermal paste if needed\\n6. Do NOT use until cooling is verified\\n\\nContinued use may cause permanent hardware damage!')
        },
        'StuckProcess': {
            title: 'Task Manager',
            description: 'Opening Task Manager to end stuck processes.',
            action: () => alert('To open Task Manager:\\n1. Press Ctrl+Shift+Esc\\n2. Find unresponsive process\\n3. Click \\'End Task\\'\\n\\nIf process won\\'t end, right-click and select \\'Go to details\\', then right-click the process and select \\'End process tree\\'.')
        },
        'JavaHeapIssue': {
            title: 'Java Heap Configuration',
            description: 'Java heap memory adjustment needed.',
            action: () => alert('JAVA HEAP MEMORY ADJUSTMENT\\n\\nFor Java applications:\\n1. Locate the application\\'s startup script or shortcut\\n2. Add or modify: -Xmx4G (for 4GB max heap)\\n3. Adjust based on available RAM\\n\\nFor Minecraft: Edit launcher settings\\nFor other Java apps: Consult application documentation')
        }
    };

    const fix = fixActions[fixType];
    if (fix) {
        fix.action();
    } else {
        alert('This fix requires manual intervention. Please follow the recommended steps.');
    }
}

function openSettingForCategory(category) {
    const settingMappings = {
        'Storage': 'ms-settings:storagesense',
        'RAM': 'ms-settings:about',
        'CPU': 'ms-settings:deviceperformance',
        'PowerPlan': 'ms-settings:powersleep',
        'Startup': 'ms-settings:startupapps',
        'Network': 'ms-settings:network',
        'Update': 'ms-settings:windowsupdate',
        'Driver': 'ms-settings:windowsupdate-options',
        'Browser': 'ms-settings:appsfeatures',
        'GPU': 'ms-settings:display',
        'AV': 'ms-settings:windowsdefender',
        'Thermal': 'ms-settings:deviceperformance',
        'Battery': 'ms-settings:batterysaver',
        'ServiceHealth': 'ms-settings:appsfeatures',
        'DNS': 'ms-settings:network-ethernet',
        'Firewall': 'ms-settings:windowsdefender'
    };

    const settingUri = settingMappings[category] || 'ms-settings:';
    openWindowsSetting(settingUri);
}
</script>
<div class="container">
<div class="header">
<h1>Performance Analysis Report</h1>
<div class="subtitle">System Diagnostic & Optimization</div>
</div>
<div class="meta">
<div class="meta-item"><span class="meta-label">Report Date:</span><span class="meta-value">$timestamp</span></div>
<div class="meta-item"><span class="meta-label">Scan Type:</span><span class="meta-value">$Tier</span></div>
<div class="meta-item"><span class="meta-label">Computer:</span><span class="meta-value">$env:COMPUTERNAME</span></div>
</div>
<div class="content">
<div class="section">
<h2>System Health Overview</h2>
<div class="metrics-grid">
<div class="metric-card">
<div class="metric-label">System Errors (7 days)</div>
<div class="metric-value">$($eventSummary.ErrorCount)</div>
</div>
<div class="metric-card">
<div class="metric-label">Warnings (7 days)</div>
<div class="metric-value">$($eventSummary.WarningCount)</div>
</div>
<div class="metric-card">
<div class="metric-label">Issues Detected</div>
<div class="metric-value">$(($Results | Where-Object { $_.Impact -gt 5 }).Count)</div>
</div>
<div class="metric-card">
<div class="metric-label">Avg Performance Score</div>
<div class="metric-value">$([math]::Round(($Results | Measure-Object Score -Average).Average,1))</div>
</div>
$(if ($fusedAlert) { @"
<div class=\"metrics-grid\">
    <div class=\"metric-card\">
        <div class=\"metric-label\">Network Fused Alert</div>
        <div class=\"metric-value\">$fusedAlert</div>
    </div>
</div>
"@ })
</div>
</div>
"@
    # Generate smart recommendations
    . $PSScriptRoot/Bottleneck.UserExperience.ps1
    $recommendations = Get-BottleneckSmartRecommendations -Results $Results
    $priorityColor = switch ($recommendations.Priority) {
        'Critical' { '#dc3545' }
        'High' { '#fd7e14' }
        'Medium' { '#ffc107' }
        default { '#28a745' }
    }
    $html += @"
<div class="section">
<h2>Technician Recommendations</h2>
<div style="background:$priorityColor;color:white;padding:20px;border-radius:8px;margin-bottom:20px;">
<h3 style="font-size:18px;margin-bottom:10px;color:white;">Priority Level: $($recommendations.Priority)</h3>
<p style="font-size:14px;line-height:1.6;">$($recommendations.Message)</p>
</div>
$(if ($recommendations.CriticalFixes.Count -gt 0) { @"
<h3 style="font-size:16px;color:#dc3545;margin:20px 0 10px 0;">🔴 Critical Fixes Required</h3>
<ul>
$(foreach ($fix in $recommendations.CriticalFixes) {
    $escapedFix = $fix -replace "'", "&#39;" -replace '"', '&quot;'
    "<li>$fix<button class='ai-help-btn' onclick='getAIHelp(`"Critical Issue`", `"$escapedFix`", `"Critical fix needed`", `"copilot`")'>Ask AI</button></li>"
})
</ul>
"@ })
$(if ($recommendations.QuickWins.Count -gt 0) { @"
<h3 style="font-size:16px;color:#28a745;margin:20px 0 10px 0;">⚡ Quick Wins (Low Effort, High Impact)</h3>
<ul>
$(foreach ($win in $recommendations.QuickWins) { "<li>$win</li>" })
</ul>
"@ })
$(if ($recommendations.LongTermActions.Count -gt 0) { @"
<h3 style="font-size:16px;color:#0c5460;margin:20px 0 10px 0;">📋 Long-Term Actions</h3>
<ul>
$(foreach ($action in $recommendations.LongTermActions) { "<li>$action</li>" })
</ul>
"@ })
</div>
<div class="section">
<h2>Recent System Events</h2>
<h3 style="font-size:16px;color:#dc3545;margin:20px 0 10px 0;">Critical Errors</h3>
<ul>
$(if ($eventSummary.RecentErrors.Count -gt 0) { foreach ($e in $eventSummary.RecentErrors) { "<li><strong>$($e.TimeCreated)</strong><br>$($e.Message)</li>" } } else { "<li>No critical errors found.</li>" })
</ul>
<h3 style="font-size:16px;color:#ffc107;margin:20px 0 10px 0;">Warnings</h3>
<ul>
$(if ($eventSummary.RecentWarnings.Count -gt 0) { foreach ($w in $eventSummary.RecentWarnings) { "<li><strong>$($w.TimeCreated)</strong><br>$($w.Message)</li>" } } else { "<li>No warnings found.</li>" })
</ul>
</div>
<div class="section">
<h2>Scan Comparison</h2>
<table>
<tr><th>Category</th><th>Current Score</th><th>Previous Score</th><th>Trend</th></tr>
$(foreach ($r in $Results) {
    $prevScore = ($prev | Where-Object { $_.Id -eq $r.Id }).Score
    $trend = if ($prevScore -ne $null) {
        if ($r.Score -gt $prevScore) { '<span class="trend-up">↑</span>' } elseif ($r.Score -lt $prevScore) { '<span class="trend-down">↓</span>' } else { '-' }
    } else { '-' }
    "<tr><td>$($r.Category)</td><td>$($r.Score)</td><td>$prevScore</td><td>$trend</td></tr>"
})
</table>
</div>
<h2>Full Scan Details</h2>
<table>
<tr><th>Category</th><th>Message</th><th>Score</th><th>Evidence</th><th>Recommended Steps</th><th>Fix</th></tr>
"@
    foreach ($r in $Results) {
        # Color-code score: 0-10=green, 11-25=yellow, 26-45=orange, 46+=red
        $scoreClass = if ($r.Score -le 10) { 'score-green' } elseif ($r.Score -le 25) { 'score-yellow' } elseif ($r.Score -le 45) { 'score-orange' } else { 'score-red' }
        $scoreCell = "<span class='$scoreClass'>$($r.Score)</span>"

        # Generate recommended steps based on check type and impact
        $recommendedSteps = ''
        if ($r.Impact -gt 5) {
            switch ($r.Id) {
                'Storage' { $recommendedSteps = 'Free up disk space by removing temporary files, uninstalling unused programs, or moving files to external storage.' }
                'RAM' { $recommendedSteps = 'Close unnecessary applications, disable startup programs, or upgrade RAM capacity.' }
                'CPU' { $recommendedSteps = 'Identify and close CPU-intensive processes, check for malware, or upgrade CPU/cooling system.' }
                'PowerPlan' { $recommendedSteps = 'Switch to High Performance power plan for maximum performance (trades power efficiency for speed).' }
                'Startup' { $recommendedSteps = 'Disable unnecessary startup programs via Task Manager > Startup tab to improve boot time.' }
                'Network' { $recommendedSteps = 'Check WiFi signal strength, restart router, update network drivers, or contact ISP if persistent.' }
                'Update' { $recommendedSteps = 'Install pending Windows updates to improve security, stability, and performance.' }
                'Driver' { $recommendedSteps = 'Update outdated drivers via Device Manager or manufacturer website, especially GPU and chipset drivers.' }
                'Browser' { $recommendedSteps = 'Update browser to latest version, disable unnecessary extensions, clear cache and cookies.' }
                'DiskSMART' { $recommendedSteps = 'CRITICAL: Backup all data immediately and replace failing drive to prevent data loss.' }
                'OSAge' { $recommendedSteps = 'Consider clean Windows reinstall or upgrade to remove accumulated software bloat and registry issues.' }
                'GPU' { $recommendedSteps = 'Update GPU drivers from manufacturer (NVIDIA/AMD/Intel) for improved graphics performance and stability.' }
                'AV' { $recommendedSteps = 'Enable Windows Defender or install reputable antivirus software to protect against malware and threats.' }
                'Tasks' { $recommendedSteps = 'Review failed scheduled tasks in Task Scheduler, disable unnecessary tasks, or troubleshoot errors.' }
                'Thermal' { $recommendedSteps = 'Clean dust from vents/fans, improve airflow, reapply thermal paste, or upgrade cooling solution.' }
                'Battery' { $recommendedSteps = 'Calibrate battery or consider replacement if wear exceeds 30% to restore runtime.' }
                'DiskFragmentation' { $recommendedSteps = 'Run disk defragmentation to consolidate fragmented files and improve HDD read/write speed.' }
                'MemoryHealth' { $recommendedSteps = 'Run Windows Memory Diagnostic, reseat RAM modules, or replace faulty memory sticks.' }
                'CPUThrottle' { $recommendedSteps = 'Improve cooling, switch to High Performance power plan, or check BIOS power settings.' }
                'ServiceHealth' { $recommendedSteps = 'Restart failed services, check Event Viewer for service errors, or reinstall affected applications.' }
                'StartupImpact' { $recommendedSteps = 'Disable high-impact startup apps in Task Manager > Startup to reduce boot time and resource usage.' }
                'WindowsFeatures' { $recommendedSteps = 'Review and enable recommended Windows services, or disable services not needed for your use case.' }
                'GroupPolicy' { $recommendedSteps = 'Review Group Policy settings with system administrator if in managed environment.' }
                'DNS' { $recommendedSteps = 'Change DNS servers to Google (8.8.8.8) or Cloudflare (1.1.1.1) for faster resolution, flush DNS cache with ipconfig /flushdns.' }
                'NetworkAdapter' { $recommendedSteps = 'Update network adapter drivers, check cable connections, verify full-duplex mode enabled, restart adapter.' }
                'Bandwidth' { $recommendedSteps = 'Identify bandwidth-hogging processes in Task Manager > Performance > Ethernet, close unnecessary network apps, enable QoS.' }
                'VPN' { $recommendedSteps = 'Disconnect VPN when not needed, choose nearby VPN server locations, disable proxy settings if not required.' }
                'Firewall' { $recommendedSteps = 'Review and remove unnecessary firewall rules, check for conflicting third-party firewall software, disable unused rules.' }
                'AntivirusHealth' { $recommendedSteps = 'CRITICAL: Enable Windows Defender real-time protection, update virus definitions, run full system scan immediately.' }
                'WindowsUpdateHealth' { $recommendedSteps = 'Start Windows Update service, install pending updates, check Event Viewer for update errors, unpause updates if paused.' }
                'SecurityBaseline' { $recommendedSteps = 'Enable UAC, enable Windows Firewall on all profiles, consider enabling BitLocker, disable guest account, strengthen password policy.' }
                'PortSecurity' { $recommendedSteps = 'Close unnecessary open ports, disable unused services, verify no unauthorized remote access tools running, run malware scan.' }
                'BrowserSecurity' { $recommendedSteps = 'Update browser to latest version, remove suspicious extensions, enable HTTPS-only mode, clear browsing data regularly.' }
                'BootTime' { $recommendedSteps = 'Disable unnecessary startup programs, update slow boot drivers, enable Fast Startup in Power Options, run Startup Repair if needed.' }
                'AppLaunch' { $recommendedSteps = 'Uninstall unused programs, clear temp files, disable unnecessary background apps, increase virtual memory if RAM is low.' }
                'UIResponsiveness' { $recommendedSteps = 'Update graphics drivers, reduce visual effects, close hung applications, check for malware, increase RAM if frequently low.' }
                'PerformanceTrends' { $recommendedSteps = 'Address degrading metrics immediately, schedule regular maintenance, monitor resource usage trends, consider hardware upgrades if multiple trends worsen.' }
                'ETW' { $recommendedSteps = 'Identify high context-switching processes, update drivers causing high interrupt rates, check for driver conflicts, optimize kernel-mode operations.' }
                'FullSMART' { $recommendedSteps = 'CRITICAL: If failure predicted, backup ALL data immediately and replace drive. Do not delay - data loss imminent!' }
                'SFC' { $recommendedSteps = 'Run elevated: sfc /scannow, then DISM /Online /Cleanup-Image /RestoreHealth, reboot after completion, re-scan to verify repair.' }
                'EventLog' { $recommendedSteps = 'Investigate repeated error patterns, update drivers causing crashes, address disk/memory errors immediately, check for malware if unusual patterns.' }
                'BackgroundProcs' { $recommendedSteps = 'End unnecessary processes, uninstall resource-intensive applications, scan for malware if suspicious processes found, use autoruns to disable startup items.' }
                'HardwareReco' { $recommendedSteps = 'Follow upgrade recommendations in priority order: SSD first (biggest impact), then RAM, then CPU/GPU. Provide customer with specific part recommendations and quotes.' }
                'CPUUtilization' { $recommendedSteps = 'End high-CPU processes in Task Manager, update applications causing high usage, scan for malware/crypto miners, consider CPU upgrade if sustained high usage.' }
                'MemoryUtilization' { $recommendedSteps = 'Close memory-hungry applications, increase RAM if consistently >90%, check for memory leaks (same app growing over time), restart long-running apps.' }
                'FanSpeed' { $recommendedSteps = 'Clean dust from vents and fans, verify fans spinning freely, replace failed fans immediately, install monitoring software (HWiNFO, OpenHardwareMonitor) for better visibility.' }
                'SystemTemperature' { $recommendedSteps = 'CRITICAL if >85°C: Shut down, clean cooling system, reapply thermal paste, verify fan operation. Replace cooling solution if thermal throttling persists.' }
                'StuckProcesses' { $recommendedSteps = 'End unresponsive processes via Task Manager, kill zombie processes with taskkill /F /PID, restart apps with excessive handles/threads, reboot if multiple stuck processes.' }
                'JavaHeapIssue' { $recommendedSteps = 'Increase Java heap with -Xmx flag, monitor for memory leaks with jmap/VisualVM, restart Java apps regularly, tune GC settings for workload.' }
                default { $recommendedSteps = 'Review evidence and take appropriate action based on impact severity.' }
            }
        }
        else {
            $recommendedSteps = '<span style="color:#28a745;font-weight:600;">✓ No action needed</span>'
        }

        $fixBtn = ''
        switch ($r.FixId) {
            'Cleanup' { $fixBtn = '<button onclick="runFix(''Cleanup'')">🔧 Open Storage Settings</button>' }
            'Retrim' { $fixBtn = '<button onclick="runFix(''Retrim'')">🔧 Optimize Drive</button>' }
            'PowerPlanHighPerformance' { $fixBtn = '<button onclick="runFix(''PowerPlanHighPerformance'')">⚡ Change Power Plan</button>' }
            'TriggerUpdate' { $fixBtn = '<button onclick="runFix(''TriggerUpdate'')">🔄 Open Windows Update</button>' }
            'Defragment' { $fixBtn = '<button onclick="runFix(''Defragment'')">🔧 Defragment Drive</button>' }
            'MemoryDiagnostic' { $fixBtn = '<button onclick="runFix(''MemoryDiagnostic'')">🔍 Memory Diagnostic</button>' }
            'RestartServices' { $fixBtn = '<button onclick="runFix(''RestartServices'')">⚙️ Manage Services</button>' }
            'HighCPUProcess' { $fixBtn = '<button onclick="runFix(''HighCPUProcess'')">📊 Task Manager</button>' }
            'HighMemoryUsage' { $fixBtn = '<button onclick="runFix(''HighMemoryUsage'')">📊 Task Manager</button>' }
            'FanIssue' { $fixBtn = '<button onclick="runFix(''FanIssue'')" style="background:#ff6b6b;">⚠️ View Instructions</button>' }
            'HighTemperature' { $fixBtn = '<button onclick="runFix(''HighTemperature'')" style="background:#dc3545;">🔥 CRITICAL</button>' }
            'StuckProcess' { $fixBtn = '<button onclick="runFix(''StuckProcess'')">❌ End Process</button>' }
            'JavaHeapIssue' { $fixBtn = '<button onclick="runFix(''JavaHeapIssue'')">☕ Java Config</button>' }
            default { $fixBtn = '' }
        }

        # Add "Open Settings" button for categories without specific fixes
        if (!$fixBtn -and $r.Impact -gt 3) {
            $categoryId = $r.Id
            $fixBtn = "<button onclick=`"openSettingForCategory('$categoryId')`" style=`"background:#6c757d;`">⚙️ Open Settings</button>"
        }

        # Add AI help button for issues with impact > 5
        $aiBtn = ''
        if ($r.Impact -gt 5) {
            $escapedEvidence = $r.Evidence -replace "'", "&#39;" -replace '"', '&quot;'
            $escapedMessage = $r.Message -replace "'", "&#39;" -replace '"', '&quot;'
            $escapedId = $r.Id -replace "'", "&#39;" -replace '"', '&quot;'
            $aiBtn = "<button class='ai-help-btn' onclick=`"getAIHelp('$escapedId', '$escapedEvidence', '$escapedMessage', 'copilot')`">Get AI Help</button>"
        }

        # Sanitize evidence for missing values (n/a fallback)
        $evidenceText = $r.Evidence
        if ($null -eq $evidenceText -or $evidenceText -eq '') { $evidenceText = 'n/a' }
        # Network avg ping fallback
        if ($r.Id -eq 'Network' -and $evidenceText -match ':\s*ms($|\b)') {
            try {
                $tc = Test-Connection -ComputerName 'www.yahoo.com' -Count 3 -ErrorAction SilentlyContinue
                if ($tc) { $avg = [math]::Round((($tc | Measure-Object -Property ResponseTime -Average).Average), 1); $evidenceText = $evidenceText -replace ':\s*ms', (": $avg ms") }
                else { $evidenceText = $evidenceText -replace ':\s*ms', ': n/a' }
            }
            catch { $evidenceText = $evidenceText -replace ':\s*ms', ': n/a' }
        }
        # Thermal evidence fallback
        $evidenceText = $evidenceText -replace 'CPU:\s*°C', 'CPU: n/a' -replace 'GPU:\s*°C', 'GPU: n/a' -replace 'Disk:\s*°C', 'Disk: n/a'
        # Battery capacity fallback
        $evidenceText = $evidenceText -replace 'Capacity:\s*/', 'Capacity: n/a'
        $html += "<tr><td>$($r.Category)</td><td>$($r.Message)</td><td>$scoreCell</td><td>$evidenceText</td><td>$recommendedSteps</td><td>$fixBtn$aiBtn</td></tr>"
    }
    # Optional AI triage stub
    if ($Global:Bottleneck_EnableAI -eq $true) {
        try {
            $net = $Results | Where-Object { $_.Category -eq 'Network' }
            $cpu = $Results | Where-Object { $_.Category -eq 'CPU' }
            $disk = $Results | Where-Object { $_.Category -eq 'Disk' }
            $summary = @()
            if ($net) { $summary += "Network checks: $($net.Count)" }
            if ($cpu) { $summary += "CPU checks: $($cpu.Count)" }
            if ($disk) { $summary += "Disk checks: $($disk.Count)" }
            $recommendations = @()
            if ($net | Where-Object { $_.Impact -gt 5 }) { $recommendations += 'Investigate DNS and router stability; test on Ethernet.' }
            if ($cpu | Where-Object { $_.Impact -gt 5 }) { $recommendations += 'Reduce background load; check throttling and power plan.' }
            if ($disk | Where-Object { $_.Impact -gt 5 }) { $recommendations += 'Check SMART, queue length; update storage drivers.' }
            $aiSection = "<div class='section'><h2>AI Triage</h2><ul>" + ($summary | ForEach-Object { "<li>$_</li>" } -join '') + "</ul><h3>Recommendations</h3><ul>" + ($recommendations | ForEach-Object { "<li>$_</li>" } -join '') + "</ul></div>"
            $html += $aiSection
        }
        catch {}
    }
    $html += "</table></div></div>"
    $html += "<div class='footer'>Generated by Bottleneck Performance Analyzer | $timestamp</div>"
    $html += "</div></body></html>"

    # Save HTML to all locations
    $html | Set-Content $htmlPath
    $html | Set-Content $userHtmlPath
    if ($oneDriveHtmlPath) {
        $html | Set-Content $oneDriveHtmlPath
    }
}
