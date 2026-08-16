# DeepSeek Harness Launcher - silent single-instance dispatcher
param(
    [string]$CustomUrl = "",
    [string]$ConfigPath = "",
    [string]$DataPath = "",
    [switch]$NoBrowser,
    [switch]$NoDialog
)

$ErrorActionPreference = "Stop"
$LauncherRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "common.ps1")

$DataDirectory = Get-LauncherDataDirectory -DataPath $DataPath
New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
$LogFile = Join-Path $DataDirectory "launcher.log"
$ServerLogFile = Join-Path $DataDirectory "server.log"
$StateFile = Join-Path $DataDirectory "server-state.json"
$DescriptorFile = Join-Path $DataDirectory "server-launch.json"
$RunnerScript = Join-Path $PSScriptRoot "run-server.ps1"
$script:OwnsMutex = $false
$script:LaunchMutex = $null

$logSha = [System.Security.Cryptography.SHA256]::Create()
try {
    $logMutexHash = ([BitConverter]::ToString($logSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($DataDirectory.ToLowerInvariant())))).Replace("-", "")
}
finally { $logSha.Dispose() }
$LogMutexName = "Local\DeepSeekHarnessLauncher-Log-$($logMutexHash.Substring(0, 24))"

function Invoke-WithLogLock {
    param([scriptblock]$Action)
    $mutex = New-Object System.Threading.Mutex($false, $LogMutexName)
    $ownsMutex = $false
    try {
        try { $ownsMutex = $mutex.WaitOne(5000, $false) }
        catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { throw "Timed out waiting for the launcher log lock." }
        & $Action
    }
    finally {
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Invoke-WithLogLock { Add-Content -LiteralPath $LogFile -Value $entry -Encoding utf8 }
}

Invoke-WithLogLock { Invoke-LogRotation -Path $LogFile }

function Show-LauncherMessage {
    param(
        [string]$Message,
        [string]$Title = "DeepSeek Harness",
        [ValidateSet("Information", "Warning", "Error")][string]$Icon = "Information"
    )
    if ($NoDialog) {
        Write-Log "$Title`: $Message"
        return
    }
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::$Icon
    ) | Out-Null
}

function Stop-WithConfigurationError {
    param([string]$Message)
    Write-Log $Message
    Show-LauncherMessage -Title (Get-LauncherText "ConfigErrorTitle") -Icon Error -Message $Message
    exit 3
}

function Test-PortOpen {
    param([string]$TargetHost, [int]$TargetPort, [int]$TimeoutMs = 300)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect($TargetHost, $TargetPort, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($pending)
        return $client.Connected
    }
    catch { return $false }
    finally { $client.Close() }
}

function Test-HarnessReady {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400 -and
            $response.Content -match '(?is)<title>\s*DeepSeek Harness(?:\s*</title>|\s*—)')
    }
    catch { return $false }
}

function Open-HarnessBrowser {
    param([string]$Url)
    if (-not $NoBrowser) { Start-Process $Url }
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
    param([int]$RootProcessId, [DateTime]$EarliestStartUtc)
    try {
        $rootProcess = Get-Process -Id $RootProcessId -ErrorAction Stop
        if ($rootProcess.StartTime.ToUniversalTime() -ge $EarliestStartUtc) {
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "SilentlyContinue"
            & taskkill.exe /PID $RootProcessId /T /F *> $null
            $taskkillExitCode = $LASTEXITCODE
            $ErrorActionPreference = $previousPreference
            if ($taskkillExitCode -eq 0) { return }
        }
    }
    catch {}
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
        [int]$Port,
        [string]$Mode,
        [string]$PackageVersion
    )
    $treeIds = @(Get-ProcessTreeIds -RootProcessId $RootProcessId)
    $listenerIds = @(Get-ListenerProcessIds -Port $Port)
    [ordered]@{
        rootProcessId = $RootProcessId
        processIds = @($treeIds)
        listenerProcessIds = @($listenerIds)
        startedAtUtc = $StartedAtUtc
        projectPath = $ProjectPath
        url = $Url
        port = $Port
        mode = $Mode
        packageVersion = $PackageVersion
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateFile -Encoding utf8
}

try {
    $ConfigFile = Initialize-LauncherConfig -LauncherRoot $LauncherRoot -DataDirectory $DataDirectory -ConfigPath $ConfigPath
    $json = Get-Content -LiteralPath $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json
}
catch {
    Write-Log "Failed to initialize or parse configuration: $_"
    $pathForMessage = if ($ConfigPath) { $ConfigPath } else { Join-Path $DataDirectory "config.json" }
    Show-LauncherMessage -Title (Get-LauncherText "ConfigErrorTitle") -Icon Error -Message (
        Get-LauncherText "ConfigReadError" @($pathForMessage, $LogFile)
    )
    exit 3
}

$mode = if ($json.mode) { ([string]$json.mode).ToLowerInvariant() } else { "npm" }
$hostAddr = if ($json.host) { [string]$json.host } else { "127.0.0.1" }
$port = if ($json.port) { [int]$json.port } else { 3080 }
$projectPath = if ($json.projectPath) { [string]$json.projectPath } else { "" }
$packageVersion = if ($json.packageVersion) { [string]$json.packageVersion } else { "" }
$extraArgs = @($json.extraArgs | ForEach-Object { [string]$_ })
$autoOpen = if ($null -ne $json.autoOpenBrowser) { [bool]$json.autoOpenBrowser } else { $true }
$timeoutSeconds = if ($json.timeoutSeconds) { [int]$json.timeoutSeconds } else { 90 }

if ($mode -notin @("npm", "source")) { Stop-WithConfigurationError (Get-LauncherText "InvalidMode" @($mode)) }
if ($port -lt 1 -or $port -gt 65535) { Stop-WithConfigurationError (Get-LauncherText "InvalidPort" @($port)) }
if ($timeoutSeconds -lt 1 -or $timeoutSeconds -gt 900) { Stop-WithConfigurationError "timeoutSeconds must be between 1 and 900." }
if ($mode -eq "npm" -and $packageVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    Stop-WithConfigurationError "packageVersion must be an exact semantic version."
}
foreach ($argument in $extraArgs) {
    if ($argument.IndexOfAny(@([char]13, [char]10, [char]0)) -ge 0) {
        Stop-WithConfigurationError "extraArgs entries cannot contain line breaks or null characters."
    }
}

$targetUrl = if ($CustomUrl) { $CustomUrl } else { "http://$($hostAddr):$($port)" }
$shouldOpen = $autoOpen -and -not $NoBrowser
Write-Log "Checking $targetUrl (mode: $mode; config: '$ConfigFile')."

# Opening an existing healthy server does not require Node.js or package tools.
if (Test-HarnessReady -Url $targetUrl) {
    Write-Log "DeepSeek Harness is already ready."
    if ($shouldOpen) { Open-HarnessBrowser -Url $targetUrl }
    exit 0
}
if (Test-PortOpen -TargetHost $hostAddr -TargetPort $port) {
    Write-Log "Port $port is occupied by a non-DSH or unhealthy service."
    Show-LauncherMessage -Title (Get-LauncherText "PortConflictTitle") -Icon Error -Message (Get-LauncherText "PortConflict" @($port))
    exit 2
}

$node = Get-NodeCompatibility
if (-not $node.Found) { Stop-WithConfigurationError (Get-LauncherText "NodeMissing") }
if (-not $node.Supported) {
    $displayVersion = if ($node.Version) { $node.Version.ToString() } else { "unknown" }
    Stop-WithConfigurationError (Get-LauncherText "NodeUnsupported" @($displayVersion))
}

if ($mode -eq "source") {
    if (-not $projectPath -or -not (Test-Path -LiteralPath $projectPath -PathType Container)) {
        Stop-WithConfigurationError (Get-LauncherText "SourcePathMissing")
    }
    $packageFile = Join-Path $projectPath "package.json"
    try {
        $sourcePackage = Get-Content -LiteralPath $packageFile -Raw -Encoding utf8 | ConvertFrom-Json
        if (-not $sourcePackage.scripts.dsh) { throw "package.json does not define scripts.dsh" }
    }
    catch { Stop-WithConfigurationError "projectPath is not a valid DeepSeek Harness checkout: $_" }
    $commandInfo = Get-Command pnpm.cmd -ErrorAction SilentlyContinue
    if (-not $commandInfo) { $commandInfo = Get-Command pnpm -ErrorAction SilentlyContinue }
    if (-not $commandInfo) { Stop-WithConfigurationError (Get-LauncherText "ToolMissing" @("pnpm", "source")) }
    $serverArguments = @("dsh", "web") + $extraArgs
    $workingDirectory = (Resolve-Path -LiteralPath $projectPath).Path
}
else {
    # Use the locally installed DeepSeek Harness profile directly instead of
    # pulling the package over the network via npx (which is slow and can fail
    # with ETARGET / timeouts on some registries).
    $commandInfo = Get-Command node -ErrorAction SilentlyContinue
    if (-not $commandInfo) { Stop-WithConfigurationError (Get-LauncherText "ToolMissing" @("node", "npm")) }
    $localBin = Join-Path $HOME ".dsh\profiles\node_modules\@deepseek-ai\dsh\lib\bin.js"
    if (-not (Test-Path -LiteralPath $localBin)) {
        Stop-WithConfigurationError "Local DeepSeek Harness install not found at '$localBin'. Reinstall the dsh profile first."
    }
    $serverArguments = @($localBin, "web") + $extraArgs
    $workingDirectory = Join-Path $HOME ".dsh\profiles"
}

$mutexSeed = "$DataDirectory|$hostAddr|$port".ToLowerInvariant()
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $mutexHash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($mutexSeed)))).Replace("-", "") }
finally { $sha.Dispose() }
$script:LaunchMutex = New-Object System.Threading.Mutex($false, "Local\DeepSeekHarnessLauncher-$($mutexHash.Substring(0, 24))")

try {
    try { $script:OwnsMutex = $script:LaunchMutex.WaitOne(0, $false) }
    catch [System.Threading.AbandonedMutexException] { $script:OwnsMutex = $true }

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
        Show-LauncherMessage -Title (Get-LauncherText "StartupTimeoutTitle") -Icon Warning -Message (
            Get-LauncherText "StartupTimeoutOther" @($timeoutSeconds, $LogFile)
        )
        exit 1
    }

    if (Test-HarnessReady -Url $targetUrl) {
        if ($shouldOpen) { Open-HarnessBrowser -Url $targetUrl }
        exit 0
    }
    if (Test-PortOpen -TargetHost $hostAddr -TargetPort $port) {
        Show-LauncherMessage -Title (Get-LauncherText "PortConflictTitle") -Icon Error -Message (Get-LauncherText "PortConflict" @($port))
        exit 2
    }

    Invoke-LogRotation -Path $ServerLogFile
    [ordered]@{
        executable = $commandInfo.Source
        arguments = @($serverArguments)
        workingDirectory = $workingDirectory
        logFile = $ServerLogFile
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $DescriptorFile -Encoding utf8

    Write-Log "Starting DeepSeek Harness in '$workingDirectory' with structured $mode mode."
    $startedAtUtc = [DateTime]::UtcNow.ToString("o")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $PSHOME "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$RunnerScript`" -DescriptorPath `"$DescriptorFile`""
    $psi.WorkingDirectory = $workingDirectory
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $serverProcess = [System.Diagnostics.Process]::Start($psi)
    Write-Log "Dispatched server process PID $($serverProcess.Id)."
    Save-ServerState -RootProcessId $serverProcess.Id -StartedAtUtc $startedAtUtc -ProjectPath $projectPath -Url $targetUrl -Port $port -Mode $mode -PackageVersion $packageVersion

    $startTime = Get-Date
    while (((Get-Date) - $startTime).TotalSeconds -lt $timeoutSeconds) {
        if (Test-HarnessReady -Url $targetUrl) {
            $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
            Save-ServerState -RootProcessId $serverProcess.Id -StartedAtUtc $startedAtUtc -ProjectPath $projectPath -Url $targetUrl -Port $port -Mode $mode -PackageVersion $packageVersion
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
    if (Test-Path -LiteralPath $StateFile) { Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue }
    Show-LauncherMessage -Title (Get-LauncherText "StartupFailedTitle") -Icon Warning -Message (
        Get-LauncherText "StartupFailed" @($timeoutSeconds, $ServerLogFile)
    )
    exit 1
}
catch {
    Write-Log "Unexpected launcher error: $_"
    Show-LauncherMessage -Title (Get-LauncherText "LauncherErrorTitle") -Icon Error -Message (Get-LauncherText "LauncherError" @($LogFile))
    exit 1
}
finally {
    if ($script:OwnsMutex -and $script:LaunchMutex) { $script:LaunchMutex.ReleaseMutex() }
    if ($script:LaunchMutex) { $script:LaunchMutex.Dispose() }
}
