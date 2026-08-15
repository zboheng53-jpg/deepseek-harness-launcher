# DeepSeek Harness Desktop Launcher - installer
param(
    [string]$ProjectPath = "",
    [string]$DesktopPath = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$LauncherRoot = Split-Path -Parent $PSScriptRoot
$ConfigFile = Join-Path $LauncherRoot "config.json"
$IconFile = Join-Path $LauncherRoot "assets\app.ico"
$VbsScript = Join-Path $LauncherRoot "scripts\launch.vbs"

if (-not $Quiet) {
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  DeepSeek Harness 一键桌面启动器 安装向导" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
}

if (-not (Test-Path -LiteralPath $VbsScript -PathType Leaf)) {
    throw "Missing launcher script: $VbsScript"
}

if (-not (Test-Path -LiteralPath $IconFile -PathType Leaf)) {
    $buildScript = Join-Path $PSScriptRoot "build_icon.py"
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python -or -not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
        throw "The icon is missing and cannot be rebuilt. Expected: $IconFile"
    }
    & $python.Source $buildScript
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $IconFile -PathType Leaf)) {
        throw "Icon generation failed."
    }
}

# Preserve user-edited settings on reinstall.
$config = [ordered]@{
    projectPath = ""
    port = 3080
    host = "127.0.0.1"
    command = "pnpm dsh web"
    autoOpenBrowser = $true
    timeoutSeconds = 90
}
if (Test-Path -LiteralPath $ConfigFile -PathType Leaf) {
    try {
        $existing = Get-Content -LiteralPath $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json
        foreach ($key in @("projectPath", "port", "host", "command", "autoOpenBrowser", "timeoutSeconds")) {
            if ($null -ne $existing.$key) { $config[$key] = $existing.$key }
        }
    }
    catch {
        throw "Invalid config.json: $($_.Exception.Message)"
    }
}

$resolvedProj = ""
if ($ProjectPath) {
    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
        throw "DeepSeek Harness project path does not exist: $ProjectPath"
    }
    $resolvedProj = (Resolve-Path -LiteralPath $ProjectPath).Path
}
elseif ($config.projectPath -and (Test-Path -LiteralPath ([string]$config.projectPath) -PathType Container)) {
    $resolvedProj = (Resolve-Path -LiteralPath ([string]$config.projectPath)).Path
}
else {
    $candidates = @(
        "D:\Projects\deepseek-harness",
        (Join-Path (Split-Path -Parent $LauncherRoot) "deepseek-harness"),
        (Join-Path $env:USERPROFILE "Projects\deepseek-harness"),
        (Join-Path $env:USERPROFILE "deepseek-harness")
    )
    $resolvedProj = $candidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
        ForEach-Object { (Resolve-Path -LiteralPath $_).Path } |
        Select-Object -First 1
}

if ($resolvedProj) {
    $packageFile = Join-Path $resolvedProj "package.json"
    if (-not (Test-Path -LiteralPath $packageFile -PathType Leaf)) {
        throw "The selected directory is not a DeepSeek Harness checkout (package.json missing): $resolvedProj"
    }
    try {
        $package = Get-Content -LiteralPath $packageFile -Raw -Encoding utf8 | ConvertFrom-Json
        if (-not $package.scripts.dsh) {
            throw "package.json does not define the 'dsh' script"
        }
    }
    catch {
        throw "The selected directory is not a valid DeepSeek Harness checkout: $($_.Exception.Message)"
    }
    if (-not (Get-Command pnpm.cmd -ErrorAction SilentlyContinue) -and -not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
        throw "pnpm is required to launch the local DeepSeek Harness checkout, but it was not found in PATH."
    }
    $config.projectPath = $resolvedProj
}
else {
    if (-not (Get-Command npx.cmd -ErrorAction SilentlyContinue) -and -not (Get-Command npx -ErrorAction SilentlyContinue)) {
        throw "No local DeepSeek Harness checkout or npx executable was found."
    }
    $config.projectPath = ""
}

$config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ConfigFile -Encoding utf8

if (-not $DesktopPath) {
    $DesktopPath = [System.Environment]::GetFolderPath("Desktop")
}
if (-not (Test-Path -LiteralPath $DesktopPath -PathType Container)) {
    New-Item -ItemType Directory -Path $DesktopPath -Force | Out-Null
}
$shortcutPath = Join-Path $DesktopPath "DeepSeek Harness.lnk"
$wscriptPath = Join-Path ([System.Environment]::GetFolderPath("System")) "wscript.exe"

$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $wscriptPath
$shortcut.Arguments = "`"$VbsScript`""
$shortcut.WorkingDirectory = $LauncherRoot
$shortcut.Description = "DeepSeek Harness AI Agent Web UI"
$shortcut.IconLocation = "$IconFile,0"
$shortcut.Save()

Write-Host "[OK] Configuration: $ConfigFile" -ForegroundColor Green
Write-Host "[OK] Desktop shortcut: $shortcutPath" -ForegroundColor Green
if ($resolvedProj) {
    Write-Host "[OK] DeepSeek Harness checkout: $resolvedProj" -ForegroundColor Green
}
else {
    Write-Host "[OK] Launch mode: npx -y @deepseek-ai/dsh web" -ForegroundColor Green
}

if (-not $Quiet) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "DeepSeek Harness 桌面启动器安装成功！`n`n桌面快捷方式：$shortcutPath",
        "安装完成",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}
