param(
    [switch]$InstallerSmoke,
    [string]$HarnessProjectPath = "",
    [switch]$Behavior
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$required = @(
    "assets\app.ico", "assets\app.png", "assets\logo.svg",
    "scripts\common.ps1", "scripts\launch.ps1", "scripts\launch.vbs",
    "scripts\run-server.ps1", "scripts\stop.ps1", "scripts\install.ps1",
    "scripts\uninstall.ps1", "scripts\diagnose.ps1",
    "config.default.json", "compatibility.json",
    "install.bat", "stop.bat", "uninstall.bat", "diagnose.bat",
    "README.md", "README.zh.md", "CONTRIBUTING.md", "SECURITY.md", "LICENSE",
    ".github\ISSUE_TEMPLATE\bug_report.yml", ".github\pull_request_template.md"
)

foreach ($relative in $required) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required file: $relative" }
}

$parseFailures = New-Object System.Collections.Generic.List[string]
foreach ($script in Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -Filter "*.ps1" -File) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in @($errors)) { $parseFailures.Add("$($script.Name): $($parseError.Message)") }
}
if ($parseFailures.Count -gt 0) { throw "PowerShell parse errors:`n$($parseFailures -join "`n")" }

$config = Get-Content -LiteralPath (Join-Path $Root "config.default.json") -Raw -Encoding utf8 | ConvertFrom-Json
foreach ($key in @("schemaVersion", "mode", "projectPath", "packageVersion", "extraArgs", "port", "host", "autoOpenBrowser", "timeoutSeconds")) {
    if ($null -eq $config.$key) { throw "config.default.json is missing '$key'" }
}
if ($config.mode -notin @("npm", "source")) { throw "config.default.json has an invalid mode" }
if ($config.projectPath -ne "") { throw "The public default projectPath must be empty" }
if ([int]$config.port -lt 1 -or [int]$config.port -gt 65535) { throw "config.default.json contains an invalid port" }
$compatibility = Get-Content -LiteralPath (Join-Path $Root "compatibility.json") -Raw -Encoding utf8 | ConvertFrom-Json
if ($compatibility.testedDshVersion -ne $config.packageVersion) { throw "Default and tested DSH versions differ" }

$trackedTextFiles = Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\.git\\|\\assets\\' -and $_.Extension -in @(".ps1", ".json", ".md", ".yml", ".yaml", ".bat", ".vbs")
}
foreach ($file in $trackedTextFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
    if ($content -match '(?i)D:\\Projects\\deepseek-harness') { throw "Author-specific path found in $($file.FullName)" }
}
if ((Get-Content -LiteralPath (Join-Path $Root "scripts\launch.ps1") -Raw -Encoding utf8) -match '\$json\.command') {
    throw "launch.ps1 must not execute a command from configuration"
}

$icoBytes = [System.IO.File]::ReadAllBytes((Join-Path $Root "assets\app.ico"))
if ($icoBytes.Length -lt 22 -or $icoBytes[0] -ne 0 -or $icoBytes[1] -ne 0 -or $icoBytes[2] -ne 1 -or $icoBytes[3] -ne 0) {
    throw "assets/app.ico has an invalid ICO header"
}
$iconCount = [BitConverter]::ToUInt16($icoBytes, 4)
if ($iconCount -lt 6) { throw "assets/app.ico should contain at least 6 sizes; found $iconCount" }

if ($InstallerSmoke) {
    if (-not $HarnessProjectPath) { throw "-HarnessProjectPath is required with -InstallerSmoke" }
    $smokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dsh-launcher-installer-" + [Guid]::NewGuid().ToString("N"))
    $smokeDesktop = Join-Path $smokeRoot "Desktop"
    $smokeData = Join-Path $smokeRoot "Data"
    New-Item -ItemType Directory -Path $smokeDesktop -Force | Out-Null
    try {
        & (Join-Path $Root "scripts\install.ps1") -ProjectPath $HarnessProjectPath -DesktopPath $smokeDesktop -DataPath $smokeData -Quiet
        $shortcutPath = Join-Path $smokeDesktop "DeepSeek Harness.lnk"
        if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { throw "Installer did not create the shortcut" }
        if (-not (Test-Path -LiteralPath (Join-Path $smokeData "config.json") -PathType Leaf)) { throw "Installer did not create AppData configuration" }
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        if ($shortcut.Arguments -notlike "*launch.vbs*") { throw "Shortcut arguments do not target launch.vbs" }
        if ($shortcut.IconLocation -notlike "*app.ico,0") { throw "Shortcut icon is incorrect" }
    }
    finally { Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

function Get-FreeTcpPort {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Wait-PortState {
    param([int]$Port, [bool]$Open, [int]$TimeoutSeconds = 10)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $pending = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
            $isOpen = $pending.AsyncWaitHandle.WaitOne(200, $false)
            if ($isOpen) { try { $client.EndConnect($pending) } catch { $isOpen = $false } }
        }
        catch { $isOpen = $false }
        finally { $client.Close() }
        if ($isOpen -eq $Open) { return }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    throw "Port $Port did not reach open=$Open"
}

if ($Behavior) {
    $testRoot = Join-Path (Join-Path $Root ".test-tmp") ("dsh-launcher-behavior-" + [Guid]::NewGuid().ToString("N"))
    $fakeBin = Join-Path $testRoot "bin"
    $fakeCheckout = Join-Path $testRoot "checkout"
    $dataDirectory = Join-Path $testRoot "data"
    New-Item -ItemType Directory -Path $fakeBin, $fakeCheckout, $dataDirectory -Force | Out-Null
    $originalPath = $env:PATH
    $foreignProcess = $null
    $concurrentConfig = $null
    $concurrentData = $null
    $timeoutRootPid = 0
    $timeoutPid = 0
    try {
        Set-Content -LiteralPath (Join-Path $fakeBin "node.cmd") -Encoding ascii -Value "@echo off`r`necho v24.0.0"
        Set-Content -LiteralPath (Join-Path $fakeBin "pnpm.cmd") -Encoding ascii -Value (
            "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake-server.ps1`" -Port %4 -MarkerFile `"%~6`" %7 %8 %9"
        )
        @'
param([int]$Port, [string]$MarkerFile, [string]$Title = "DeepSeek Harness", [switch]$NoListen)
Add-Content -LiteralPath $MarkerFile -Value $PID -Encoding ascii
if ($NoListen) { Start-Sleep -Seconds 30; exit 0 }
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $buffer = New-Object byte[] 4096
            [void]$stream.Read($buffer, 0, $buffer.Length)
            $body = "<html><head><title>$Title</title></head><body>ok</body></html>"
            $bytes = [Text.Encoding]::UTF8.GetBytes($body)
            $headers = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/html`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
            $stream.Write($headers, 0, $headers.Length)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        catch {}
        finally { $client.Close() }
    }
}
finally { $listener.Stop() }
'@ | Set-Content -LiteralPath (Join-Path $fakeBin "fake-server.ps1") -Encoding utf8
        '{"scripts":{"dsh":"fake"}}' | Set-Content -LiteralPath (Join-Path $fakeCheckout "package.json") -Encoding utf8
        $env:PATH = "$fakeBin;$originalPath"

        $port = Get-FreeTcpPort
        $marker = Join-Path $testRoot "starts.txt"
        $configFile = Join-Path $testRoot "config.json"
        [ordered]@{
            schemaVersion = 1; mode = "source"; projectPath = $fakeCheckout; packageVersion = "0.1.0-rc.5"
            extraArgs = @("-Port", "$port", "-MarkerFile", $marker); port = $port; host = "127.0.0.1"
            autoOpenBrowser = $false; timeoutSeconds = 10
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configFile -Encoding utf8

        & (Join-Path $Root "scripts\launch.ps1") -ConfigPath $configFile -DataPath $dataDirectory -NoBrowser -NoDialog
        if ($LASTEXITCODE -ne 0) { throw "Cold start failed with exit code $LASTEXITCODE" }
        Wait-PortState -Port $port -Open $true
        if (@(Get-Content -LiteralPath $marker).Count -ne 1) { throw "Cold start launched more than one server" }

        & (Join-Path $Root "scripts\launch.ps1") -ConfigPath $configFile -DataPath $dataDirectory -NoBrowser -NoDialog
        if ($LASTEXITCODE -ne 0) { throw "Hot activation failed with exit code $LASTEXITCODE" }
        if (@(Get-Content -LiteralPath $marker).Count -ne 1) { throw "Hot activation launched a duplicate server" }

        & (Join-Path $Root "scripts\stop.ps1") -ConfigPath $configFile -DataPath $dataDirectory -Quiet
        if ($LASTEXITCODE -ne 0) { throw "Tracked stop failed with exit code $LASTEXITCODE" }
        Wait-PortState -Port $port -Open $false

        $concurrentPort = Get-FreeTcpPort
        $concurrentMarker = Join-Path $testRoot "concurrent-starts.txt"
        $concurrentConfig = Join-Path $testRoot "concurrent-config.json"
        $concurrentData = Join-Path $testRoot "concurrent-data"
        [ordered]@{
            schemaVersion = 1; mode = "source"; projectPath = $fakeCheckout; packageVersion = "0.1.0-rc.5"
            extraArgs = @("-Port", "$concurrentPort", "-MarkerFile", $concurrentMarker)
            port = $concurrentPort; host = "127.0.0.1"; autoOpenBrowser = $false; timeoutSeconds = 30
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $concurrentConfig -Encoding utf8
        $launcherArguments = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $Root "scripts\launch.ps1"),
            "-ConfigPath", $concurrentConfig, "-DataPath", $concurrentData, "-NoBrowser", "-NoDialog"
        )
        $firstLaunch = Start-Process -FilePath (Join-Path $PSHOME "powershell.exe") -ArgumentList $launcherArguments -WindowStyle Hidden -PassThru
        $secondLaunch = Start-Process -FilePath (Join-Path $PSHOME "powershell.exe") -ArgumentList $launcherArguments -WindowStyle Hidden -PassThru
        if (-not $firstLaunch.WaitForExit(25000) -or -not $secondLaunch.WaitForExit(25000)) {
            throw "Concurrent launchers did not finish"
        }
        if ($firstLaunch.ExitCode -ne 0 -or $secondLaunch.ExitCode -ne 0) {
            throw "Concurrent launchers returned $($firstLaunch.ExitCode) and $($secondLaunch.ExitCode)"
        }
        if (@(Get-Content -LiteralPath $concurrentMarker).Count -ne 1) { throw "Concurrent cold start launched a duplicate server" }
        & (Join-Path $Root "scripts\stop.ps1") -ConfigPath $concurrentConfig -DataPath $concurrentData -Quiet
        if ($LASTEXITCODE -ne 0) { throw "Concurrent-start server could not be stopped" }
        Wait-PortState -Port $concurrentPort -Open $false

        $foreignPort = Get-FreeTcpPort
        $foreignMarker = Join-Path $testRoot "foreign.txt"
        $foreignProcess = Start-Process -FilePath (Join-Path $PSHOME "powershell.exe") -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $fakeBin "fake-server.ps1"),
            "-Port", "$foreignPort", "-MarkerFile", $foreignMarker, "-Title", "Unrelated Service"
        ) -WindowStyle Hidden -PassThru
        Wait-PortState -Port $foreignPort -Open $true
        $foreignConfig = Join-Path $testRoot "foreign-config.json"
        [ordered]@{
            schemaVersion = 1; mode = "source"; projectPath = $fakeCheckout; packageVersion = "0.1.0-rc.5"
            extraArgs = @(); port = $foreignPort; host = "127.0.0.1"; autoOpenBrowser = $false; timeoutSeconds = 2
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $foreignConfig -Encoding utf8
        & (Join-Path $Root "scripts\launch.ps1") -ConfigPath $foreignConfig -DataPath (Join-Path $testRoot "foreign-data") -NoBrowser -NoDialog
        if ($LASTEXITCODE -ne 2) { throw "Port conflict returned $LASTEXITCODE instead of 2" }
        & (Join-Path $Root "scripts\stop.ps1") -ConfigPath $foreignConfig -DataPath (Join-Path $testRoot "foreign-data") -Quiet
        if ($LASTEXITCODE -ne 2) { throw "Safe stop did not report the unrelated listener" }
        if ($foreignProcess.HasExited) { throw "Safe stop terminated an unrelated listener" }
        Wait-PortState -Port $foreignPort -Open $true

        $timeoutPort = Get-FreeTcpPort
        $timeoutMarker = Join-Path $testRoot "timeout.txt"
        $timeoutConfig = Join-Path $testRoot "timeout-config.json"
        [ordered]@{
            schemaVersion = 1; mode = "source"; projectPath = $fakeCheckout; packageVersion = "0.1.0-rc.5"
            extraArgs = @("-Port", "$timeoutPort", "-MarkerFile", $timeoutMarker, "-NoListen"); port = $timeoutPort
            host = "127.0.0.1"; autoOpenBrowser = $false; timeoutSeconds = 1
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $timeoutConfig -Encoding utf8
        $timeoutData = Join-Path $testRoot "timeout-data"
        & (Join-Path $Root "scripts\launch.ps1") -ConfigPath $timeoutConfig -DataPath $timeoutData -NoBrowser -NoDialog
        if ($LASTEXITCODE -ne 1) { throw "Startup timeout returned $LASTEXITCODE instead of 1" }
        if (Test-Path -LiteralPath (Join-Path $timeoutData "server-state.json")) { throw "Timeout left stale server state" }
        $timeoutLog = Get-Content -LiteralPath (Join-Path $timeoutData "launcher.log") -Raw -Encoding utf8
        if ($timeoutLog -notmatch 'Dispatched server process PID (\d+)') { throw "Timeout test could not identify the runner PID" }
        $timeoutRootPid = [int]$Matches[1]
        $cleanupDeadline = (Get-Date).AddSeconds(3)
        while ((Get-Process -Id $timeoutRootPid -ErrorAction SilentlyContinue) -and (Get-Date) -lt $cleanupDeadline) {
            Start-Sleep -Milliseconds 100
        }
        if (Get-Process -Id $timeoutRootPid -ErrorAction SilentlyContinue) { throw "Timeout did not clean up the server runner" }
        $timeoutPid = [int](Get-Content -LiteralPath $timeoutMarker | Select-Object -First 1)
        # Restricted Windows sandboxes can deny taskkill /T even for a child process;
        # clean that test-only descendant if the native tree operation was blocked.
        if (Get-Process -Id $timeoutPid -ErrorAction SilentlyContinue) {
            Stop-Process -Id $timeoutPid -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        if ($configFile -and (Test-Path -LiteralPath (Join-Path $dataDirectory "server-state.json"))) {
            & (Join-Path $Root "scripts\stop.ps1") -ConfigPath $configFile -DataPath $dataDirectory -Quiet
        }
        if ($concurrentConfig -and $concurrentData -and (Test-Path -LiteralPath (Join-Path $concurrentData "server-state.json"))) {
            & (Join-Path $Root "scripts\stop.ps1") -ConfigPath $concurrentConfig -DataPath $concurrentData -Quiet
        }
        foreach ($testPid in @($timeoutPid, $timeoutRootPid)) {
            if ($testPid -gt 0 -and (Get-Process -Id $testPid -ErrorAction SilentlyContinue)) {
                Stop-Process -Id $testPid -Force -ErrorAction SilentlyContinue
            }
        }
        $env:PATH = $originalPath
        if ($foreignProcess -and -not $foreignProcess.HasExited) { Stop-Process -Id $foreignProcess.Id -Force -ErrorAction SilentlyContinue }
        if ($env:DSH_LAUNCHER_KEEP_TEST_TEMP -eq "1") {
            Write-Host "Behavior test data preserved at: $testRoot" -ForegroundColor Yellow
        }
        else {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "Verification passed ($iconCount icon sizes$(if ($Behavior) { ', behavior tests' } else { '' }))." -ForegroundColor Green
exit 0
