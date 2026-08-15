# DeepSeek Harness Desktop Launcher - silent single-instance dispatcher
param(
    [string]$CustomUrl = "",
    [string]$ConfigPath = "",
    [switch]$NoBrowser,
    [switch]$NoDialog
)

$ErrorActionPreference = "Stop"
$LauncherRoot = Split-Path -Parent $PSScriptRoot
$ConfigFile = if ($ConfigPath) { $ConfigPath } else { Join-Path $LauncherRoot "config.json" }
$LogsDir = Join-Path $LauncherRoot "logs"
$LogFile = Join-Path $LogsDir "launcher.log"
$ServerLogFile = Join-Path $LogsDir "server.log"
$StateFile = Join-Path $LogsDir "server-state.json"
$script:OwnsMutex = $false
$script:LaunchMutex = $null

New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $LogFile -Value "[$timestamp] $Message" -Encoding utf8
}

function Show-LauncherMessage {
    param(
        [string]$Message,
        [string]$Title = "DeepSeek Harness",
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Icon = "Information"
    )
    if ($NoDialog) {
        Write-Log "$Title`: $Message"
        return
    }
    Add-Type -AssemblyName System.Windows.Forms
    $iconValue = [System.Windows.Forms.MessageBoxIcon]::$Icon
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $iconValue
    ) | Out-Null
}

function Test-PortOpen {
    param(
        [string]$TargetHost,
        [int]$TargetPort,
        [int]$TimeoutMs = 300
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect($TargetHost, $TargetPort, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($pending)
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Test-HarnessReady {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400 -and
            $response.Content -match '(?is)<title>\s*DeepSeek Harness(?:\s*</title>|\s*—)')
    }
    catch {
        return $false
    }
}

function Open-HarnessBrowser {
    param([string]$Url)
    if (-not $NoBrowser) {
        Start-Process $Url
    }
}

function Get-ProcessTreeIds {
    param([int]$RootProcessId)
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $ids = New-Object System.Collections.Generic.List[int]
    $queue = New-Object System.Collections.Generic.Queue[int]
    $queue.Enqueue($RootProcessId)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($ids.Contains($current)) { continue }
        $ids.Add($current)
        foreach ($child in $all | Where-Object { $_.ParentProcessId -eq $current }) {
            $queue.Enqueue([int]$child.ProcessId)
        }
    }
    return @($ids)
}

function Stop-StartedProcessTree {
    param(
        [int]$RootProcessId,
        [DateTime]$EarliestStartUtc
    )
    $treeIds = @(Get-ProcessTreeIds -RootProcessId $RootProcessId)
    [Array]::Reverse($treeIds)
    foreach ($processId in $treeIds) {
        try {
            $process = Get-Process -Id $processId -ErrorAction Stop
            if ($process.StartTime.ToUniversalTime() -ge $EarliestStartUtc) {
                Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
            }
        }
        catch {}
    }
}

function Save-ServerState {
    param(
        [int]$RootProcessId,
        [string]$StartedAtUtc,
        [string]$ProjectPath,
        [string]$Url,
        [int]$Port
    )
    $treeIds = @(Get-ProcessTreeIds -RootProcessId $RootProcessId)
    $listenerIds = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique)
    $state = [ordered]@{
        rootProcessId = $RootProcessId
        processIds = @($treeIds)
        listenerProcessIds = @($listenerIds)
        startedAtUtc = $StartedAtUtc
        projectPath = $ProjectPath
        url = $Url
        port = $Port
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateFile -Encoding utf8
}

# Read configuration.
$hostAddr = "127.0.0.1"
$port = 3080
$projectPath = ""
$command = "pnpm dsh web"
$autoOpen = $true
$timeoutSeconds = 90

if (Test-Path -LiteralPath $ConfigFile) {
    try {
        $json = Get-Content -LiteralPath $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json
        if ($json.host) { $hostAddr = [string]$json.host }
        if ($json.port) { $port = [int]$json.port }
        if ($json.projectPath) { $projectPath = [string]$json.projectPath }
        if ($json.command) { $command = [string]$json.command }
        if ($null -ne $json.autoOpenBrowser) { $autoOpen = [bool]$json.autoOpenBrowser }
        if ($json.timeoutSeconds) { $timeoutSeconds = [int]$json.timeoutSeconds }
    }
    catch {
        Write-Log "Failed to parse config file '$ConfigFile': $_"
        Show-LauncherMessage -Title "配置错误" -Icon Error -Message "无法读取启动器配置。`n`n$ConfigFile`n`n详情请查看：$LogFile"
        exit 3
    }
}

if ($port -lt 1 -or $port -gt 65535) {
    Show-LauncherMessage -Title "配置错误" -Icon Error -Message "端口必须在 1 到 65535 之间；当前值为 $port。"
    exit 3
}

if (-not $projectPath -or -not (Test-Path -LiteralPath $projectPath -PathType Container)) {
    $candidates = @(
        "D:\Projects\deepseek-harness",
        (Join-Path (Split-Path -Parent $LauncherRoot) "deepseek-harness"),
        (Join-Path $env:USERPROFILE "Projects\deepseek-harness"),
        (Join-Path $env:USERPROFILE "deepseek-harness")
    )
    $projectPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
}

$targetUrl = if ($CustomUrl) { $CustomUrl } else { "http://$($hostAddr):$($port)" }
$shouldOpen = $autoOpen -and -not $NoBrowser
Write-Log "Checking $targetUrl (project: '$projectPath')."

# Reuse a healthy DSH instance, but never mistake an unrelated service for DSH.
if (Test-HarnessReady -Url $targetUrl) {
    Write-Log "DeepSeek Harness is already ready."
    if ($shouldOpen) { Open-HarnessBrowser -Url $targetUrl }
    exit 0
}
if (Test-PortOpen -TargetHost $hostAddr -TargetPort $port) {
    Write-Log "Port $port is occupied by a non-DSH or unhealthy service."
    Show-LauncherMessage -Title "端口冲突" -Icon Error -Message "端口 $port 已被其他服务占用，且该服务不是可识别的 DeepSeek Harness。`n`n请释放端口或修改 config.json。"
    exit 2
}

# A named mutex closes the race between two cold-start double-clicks.
$mutexSeed = "$LauncherRoot|$hostAddr|$port".ToLowerInvariant()
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $mutexHash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($mutexSeed)))).Replace("-", "")
}
finally {
    $sha.Dispose()
}
$script:LaunchMutex = New-Object System.Threading.Mutex($false, "Local\DeepSeekHarnessLauncher-$($mutexHash.Substring(0, 24))")
try {
    try {
        $script:OwnsMutex = $script:LaunchMutex.WaitOne(0, $false)
    }
    catch [System.Threading.AbandonedMutexException] {
        $script:OwnsMutex = $true
    }

    if (-not $script:OwnsMutex) {
        Write-Log "Another launcher instance is starting the server; waiting for readiness."
        $waitStart = Get-Date
        while (((Get-Date) - $waitStart).TotalSeconds -lt $timeoutSeconds) {
            if (Test-HarnessReady -Url $targetUrl) {
                Write-Log "The other launcher instance completed startup."
                if ($shouldOpen) { Open-HarnessBrowser -Url $targetUrl }
                exit 0
            }
            Start-Sleep -Milliseconds 250
        }
        Show-LauncherMessage -Title "启动超时" -Icon Warning -Message "另一启动任务未能在 ${timeoutSeconds} 秒内启动 DeepSeek Harness。`n`n请查看：$LogFile"
        exit 1
    }

    # Recheck after acquiring the mutex because another process may have won the race.
    if (Test-HarnessReady -Url $targetUrl) {
        if ($shouldOpen) { Open-HarnessBrowser -Url $targetUrl }
        exit 0
    }
    if (Test-PortOpen -TargetHost $hostAddr -TargetPort $port) {
        Show-LauncherMessage -Title "端口冲突" -Icon Error -Message "端口 $port 已被其他服务占用。请释放端口或修改 config.json。"
        exit 2
    }

    if ($projectPath) {
        $startScript = "cd /d `"$projectPath`" && $command 1>>`"$ServerLogFile`" 2>&1"
        $workingDirectory = $projectPath
    }
    else {
        $startScript = "npx -y @deepseek-ai/dsh web 1>>`"$ServerLogFile`" 2>&1"
        $workingDirectory = $LauncherRoot
    }

    Write-Log "Starting DeepSeek Harness in '$workingDirectory'."
    $startedAtUtc = [DateTime]::UtcNow.ToString("o")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = "/d /c $startScript"
    $psi.WorkingDirectory = $workingDirectory
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $serverProcess = [System.Diagnostics.Process]::Start($psi)
    Write-Log "Dispatched server process PID $($serverProcess.Id)."
    Save-ServerState -RootProcessId $serverProcess.Id -StartedAtUtc $startedAtUtc -ProjectPath $projectPath -Url $targetUrl -Port $port

    $startTime = Get-Date
    while (((Get-Date) - $startTime).TotalSeconds -lt $timeoutSeconds) {
        if (Test-HarnessReady -Url $targetUrl) {
            $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
            Save-ServerState -RootProcessId $serverProcess.Id -StartedAtUtc $startedAtUtc -ProjectPath $projectPath -Url $targetUrl -Port $port
            Write-Log "Server ready in ${elapsed}s."
            if ($shouldOpen) { Open-HarnessBrowser -Url $targetUrl }
            exit 0
        }
        if ($serverProcess.HasExited) {
            Write-Log "Server process exited early with code $($serverProcess.ExitCode)."
            break
        }
        Start-Sleep -Milliseconds 250
    }

    Write-Log "Server failed to become ready within ${timeoutSeconds}s; stopping the incomplete process tree."
    Stop-StartedProcessTree -RootProcessId $serverProcess.Id -EarliestStartUtc ([DateTime]::Parse($startedAtUtc).ToUniversalTime().AddSeconds(-5))
    if (Test-Path -LiteralPath $StateFile) {
        Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
    }
    Show-LauncherMessage -Title "启动失败" -Icon Warning -Message "DeepSeek Harness 未能在 ${timeoutSeconds} 秒内就绪。`n`n请查看服务器日志：`n$ServerLogFile"
    exit 1
}
catch {
    Write-Log "Unexpected launcher error: $_"
    Show-LauncherMessage -Title "启动器错误" -Icon Error -Message "启动 DeepSeek Harness 时发生错误。`n`n详情请查看：$LogFile"
    exit 1
}
finally {
    if ($script:OwnsMutex -and $script:LaunchMutex) {
        $script:LaunchMutex.ReleaseMutex()
    }
    if ($script:LaunchMutex) {
        $script:LaunchMutex.Dispose()
    }
}
