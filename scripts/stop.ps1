# DeepSeek Harness Desktop Launcher - safely stop a tracked DSH server
param(
    [string]$ConfigPath = "",
    [switch]$Quiet
)

$LauncherRoot = Split-Path -Parent $PSScriptRoot
$ConfigFile = if ($ConfigPath) { $ConfigPath } else { Join-Path $LauncherRoot "config.json" }
$StateFile = Join-Path $LauncherRoot "logs\server-state.json"
$port = 3080
$projectPath = ""

if (Test-Path -LiteralPath $ConfigFile) {
    try {
        $json = Get-Content -LiteralPath $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json
        if ($json.port) { $port = [int]$json.port }
        if ($json.projectPath) { $projectPath = [string]$json.projectPath }
    }
    catch {}
}

function Test-HarnessCommandLine {
    param(
        [string]$CommandLine,
        [string]$ExpectedProjectPath
    )
    if (-not $CommandLine) { return $false }
    $looksLikeWebCommand = $CommandLine -match '(?i)(\bdsh(?:\.cmd)?\s+web\b|apps[\\/]cli[\\/]src[\\/]bin\.ts.*\bweb\b|@deepseek-ai[\\/]dsh.*\bweb\b)'
    if (-not $looksLikeWebCommand) { return $false }
    if (-not $ExpectedProjectPath) { return $true }
    return ($CommandLine.IndexOf($ExpectedProjectPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $CommandLine -match '(?i)(apps[\\/]cli[\\/]src[\\/]bin\.ts.*\bweb\b|@deepseek-ai[\\/]dsh.*\bweb\b)')
}

function Test-ProcessNotReused {
    param(
        [int]$ProcessId,
        [DateTime]$EarliestStartUtc
    )
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        return ($proc.StartTime.ToUniversalTime() -ge $EarliestStartUtc)
    }
    catch {
        return $false
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

$stopped = New-Object System.Collections.Generic.List[int]
$skippedUnrelatedListener = $false
$trackedIds = @()
$earliestStartUtc = [DateTime]::MinValue

if (Test-Path -LiteralPath $StateFile) {
    try {
        $state = Get-Content -LiteralPath $StateFile -Raw -Encoding utf8 | ConvertFrom-Json
        if ($state.startedAtUtc) {
            $earliestStartUtc = ([DateTime]::Parse([string]$state.startedAtUtc)).ToUniversalTime().AddSeconds(-5)
        }
        $trackedIds = @($state.processIds) + @($state.listenerProcessIds) + @($state.rootProcessId) |
            Where-Object { $_ -and [int]$_ -gt 0 } |
            ForEach-Object { [int]$_ } |
            Select-Object -Unique
        if ($state.rootProcessId -and [int]$state.rootProcessId -gt 0) {
            $liveTreeIds = @(Get-ProcessTreeIds -RootProcessId ([int]$state.rootProcessId))
            $trackedIds = @($trackedIds) + @($liveTreeIds) | Select-Object -Unique
        }
    }
    catch {
        $trackedIds = @()
    }
}

# Stop only PIDs recorded by this launcher, and reject PID reuse by start time.
$orderedTrackedIds = @($trackedIds)
[Array]::Reverse($orderedTrackedIds)
foreach ($processId in $orderedTrackedIds) {
    if (Test-ProcessNotReused -ProcessId $processId -EarliestStartUtc $earliestStartUtc) {
        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
            $stopped.Add($processId)
        }
        catch {}
    }
}

Start-Sleep -Milliseconds 250

# Recover safely when the state file is absent: only stop a listener whose command
# line positively identifies it as `dsh web`. Never kill an arbitrary port owner.
$listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique)
foreach ($listenerId in $listeners) {
    if ($listenerId -le 0 -or $stopped.Contains([int]$listenerId)) { continue }
    $info = Get-CimInstance Win32_Process -Filter "ProcessId = $listenerId" -ErrorAction SilentlyContinue
    if ($info -and (Test-HarnessCommandLine -CommandLine $info.CommandLine -ExpectedProjectPath $projectPath)) {
        try {
            Stop-Process -Id $listenerId -Force -ErrorAction Stop
            $stopped.Add([int]$listenerId)
        }
        catch {}
    }
    else {
        $skippedUnrelatedListener = $true
    }
}

if (Test-Path -LiteralPath $StateFile) {
    Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
}

if (-not $Quiet) {
    Add-Type -AssemblyName System.Windows.Forms
    if ($stopped.Count -gt 0) {
        $message = "DeepSeek Harness 后台服务已停止。`n`n已终止进程：$($stopped -join ', ')"
        $title = "服务已停止"
        $icon = [System.Windows.Forms.MessageBoxIcon]::Information
    }
    elseif ($skippedUnrelatedListener) {
        $message = "端口 $port 正在使用，但占用者无法识别为 DeepSeek Harness。为避免误杀进程，启动器没有终止它。"
        $title = "未停止其他服务"
        $icon = [System.Windows.Forms.MessageBoxIcon]::Warning
    }
    else {
        $message = "未检测到由此启动器管理的 DeepSeek Harness 服务。"
        $title = "服务未运行"
        $icon = [System.Windows.Forms.MessageBoxIcon]::Information
    }
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        $title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    ) | Out-Null
}

if ($skippedUnrelatedListener) { exit 2 }
exit 0
