# Shared helpers for the DeepSeek Harness Launcher scripts.

function Get-LauncherDataDirectory {
    param([string]$DataPath = "")
    if ($DataPath) { return [System.IO.Path]::GetFullPath($DataPath) }
    if (-not $env:LOCALAPPDATA) { throw "LOCALAPPDATA is not available." }
    return (Join-Path $env:LOCALAPPDATA "DeepSeekHarnessLauncher")
}

function Initialize-LauncherConfig {
    param(
        [string]$LauncherRoot,
        [string]$DataDirectory,
        [string]$ConfigPath = ""
    )
    $defaultFile = Join-Path $LauncherRoot "config.default.json"
    if (-not (Test-Path -LiteralPath $defaultFile -PathType Leaf)) {
        throw "Missing default configuration: $defaultFile"
    }
    $target = if ($ConfigPath) { [System.IO.Path]::GetFullPath($ConfigPath) } else { Join-Path $DataDirectory "config.json" }
    $parent = Split-Path -Parent $target
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        Copy-Item -LiteralPath $defaultFile -Destination $target
    }
    return $target
}

function Get-NodeCompatibility {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) { $node = Get-Command node.exe -ErrorAction SilentlyContinue }
    if (-not $node) {
        return [pscustomobject]@{ Found = $false; Supported = $false; Version = $null; Path = $null }
    }
    try {
        $raw = (& $node.Source --version 2>$null | Select-Object -First 1)
        $version = [version](([string]$raw).Trim().TrimStart("v"))
        $supported = (($version.Major -eq 22 -and $version -ge [version]"22.19.0") -or $version.Major -ge 24)
        return [pscustomobject]@{ Found = $true; Supported = $supported; Version = $version; Path = $node.Source }
    }
    catch {
        return [pscustomobject]@{ Found = $true; Supported = $false; Version = $null; Path = $node.Source }
    }
}

function Get-LauncherLanguage {
    if ([System.Globalization.CultureInfo]::CurrentUICulture.Name -like "zh*") { return "zh" }
    return "en"
}

function Get-LauncherText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )
    $texts = @{
        en = @{
            ConfigErrorTitle = "Configuration error"
            ConfigReadError = "The launcher configuration could not be read.`n`n{0}`n`nSee: {1}"
            InvalidPort = "The port must be between 1 and 65535; current value: {0}."
            InvalidMode = "Mode must be 'npm' or 'source'; current value: {0}."
            SourcePathMissing = "Source mode requires a valid DeepSeek Harness checkout in projectPath."
            NodeMissing = "Node.js is required but was not found in PATH. Install a supported Node.js release and try again."
            NodeUnsupported = "Node.js {0} is unsupported. DeepSeek Harness requires Node.js ^22.19.0 or >=24.0.0."
            ToolMissing = "{0} is required for {1} mode but was not found in PATH."
            PortConflictTitle = "Port conflict"
            PortConflict = "Port {0} is occupied by another or unrecognized service.`n`nFree the port or update your launcher configuration."
            StartupTimeoutTitle = "Startup timed out"
            StartupTimeoutOther = "Another launcher did not start DeepSeek Harness within {0} seconds.`n`nSee: {1}"
            StartupFailedTitle = "Startup failed"
            StartupFailed = "DeepSeek Harness did not become ready within {0} seconds.`n`nServer log:`n{1}"
            LauncherErrorTitle = "Launcher error"
            LauncherError = "DeepSeek Harness could not be started.`n`nSee: {0}"
            InstalledTitle = "Installation complete"
            Installed = "DeepSeek Harness Launcher was installed.`n`nDesktop shortcut: {0}`nConfiguration: {1}"
            StoppedTitle = "Service stopped"
            Stopped = "The DeepSeek Harness background service was stopped.`n`nProcesses: {0}"
            NotStoppedTitle = "Other service not stopped"
            NotStopped = "Port {0} is in use, but its owner could not be identified as DeepSeek Harness. It was left running."
            NotRunningTitle = "Service not running"
            NotRunning = "No DeepSeek Harness service managed by this launcher was found."
            UninstalledTitle = "Uninstall complete"
            Uninstalled = "The DeepSeek Harness desktop shortcut was removed. User configuration and logs were preserved in:`n{0}"
        }
        zh = @{
            ConfigErrorTitle = "配置错误"
            ConfigReadError = "无法读取启动器配置。`n`n{0}`n`n详情请查看：{1}"
            InvalidPort = "端口必须在 1 到 65535 之间；当前值为 {0}。"
            InvalidMode = "mode 必须是 npm 或 source；当前值为 {0}。"
            SourcePathMissing = "source 模式要求 projectPath 指向有效的 DeepSeek Harness 源码目录。"
            NodeMissing = "未在 PATH 中找到 Node.js。请安装受支持的 Node.js 版本后重试。"
            NodeUnsupported = "不支持 Node.js {0}。DeepSeek Harness 要求 Node.js ^22.19.0 或 >=24.0.0。"
            ToolMissing = "{1} 模式需要 {0}，但未在 PATH 中找到。"
            PortConflictTitle = "端口冲突"
            PortConflict = "端口 {0} 已被其他或无法识别的服务占用。`n`n请释放端口或修改启动器配置。"
            StartupTimeoutTitle = "启动超时"
            StartupTimeoutOther = "另一启动任务未能在 {0} 秒内启动 DeepSeek Harness。`n`n请查看：{1}"
            StartupFailedTitle = "启动失败"
            StartupFailed = "DeepSeek Harness 未能在 {0} 秒内就绪。`n`n服务器日志：`n{1}"
            LauncherErrorTitle = "启动器错误"
            LauncherError = "启动 DeepSeek Harness 时发生错误。`n`n详情请查看：{0}"
            InstalledTitle = "安装完成"
            Installed = "DeepSeek Harness 启动器安装成功。`n`n桌面快捷方式：{0}`n配置文件：{1}"
            StoppedTitle = "服务已停止"
            Stopped = "DeepSeek Harness 后台服务已停止。`n`n已终止进程：{0}"
            NotStoppedTitle = "未停止其他服务"
            NotStopped = "端口 {0} 正在使用，但占用者无法识别为 DeepSeek Harness；为避免误杀，已保留该进程。"
            NotRunningTitle = "服务未运行"
            NotRunning = "未检测到由此启动器管理的 DeepSeek Harness 服务。"
            UninstalledTitle = "卸载完成"
            Uninstalled = "DeepSeek Harness 桌面快捷方式已删除。用户配置和日志仍保存在：`n{0}"
        }
    }
    $language = Get-LauncherLanguage
    $template = $texts[$language][$Key]
    if ($null -eq $template) { throw "Unknown localized text key: $Key" }
    if ($Arguments.Count -eq 0) { return $template }
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $template, $Arguments)
}

function Invoke-LogRotation {
    param(
        [string]$Path,
        [long]$MaximumBytes = 2097152,
        [int]$Keep = 3
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt $MaximumBytes) { return }
    $oldest = "$Path.$Keep"
    if (Test-Path -LiteralPath $oldest) { Remove-Item -LiteralPath $oldest -Force }
    for ($index = $Keep - 1; $index -ge 1; $index--) {
        $source = "$Path.$index"
        if (Test-Path -LiteralPath $source) { Move-Item -LiteralPath $source -Destination "$Path.$($index + 1)" -Force }
    }
    Move-Item -LiteralPath $Path -Destination "$Path.1" -Force
}

function Get-ListenerProcessIds {
    param([int]$Port)
    $ids = @()
    try {
        $ids = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop |
            Select-Object -ExpandProperty OwningProcess -Unique)
    }
    catch {}
    if ($ids.Count -gt 0) { return @($ids) }

    # NetTCPConnection can be unavailable in restricted Windows sessions. Netstat
    # is slower but provides a safe read-only fallback for listener ownership.
    $pattern = "^\s*TCP\s+\S+:$([regex]::Escape([string]$Port))\s+\S+\s+LISTENING\s+(\d+)\s*$"
    foreach ($line in @(netstat.exe -ano -p tcp 2>$null)) {
        if ($line -match $pattern) { $ids += [int]$Matches[1] }
    }
    return @($ids | Where-Object { $_ -gt 0 } | Select-Object -Unique)
}
