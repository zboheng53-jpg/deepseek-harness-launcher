# DeepSeek Harness Launcher - installer
param(
    [ValidateSet("", "npm", "source")][string]$Mode = "",
    [string]$ProjectPath = "",
    [string]$PackageVersion = "",
    [string]$DesktopPath = "",
    [string]$ConfigPath = "",
    [string]$DataPath = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$LauncherRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "common.ps1")

$DataDirectory = Get-LauncherDataDirectory -DataPath $DataPath
New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
$DefaultConfigFile = Join-Path $LauncherRoot "config.default.json"
$TargetConfigFile = if ($ConfigPath) { [System.IO.Path]::GetFullPath($ConfigPath) } else { Join-Path $DataDirectory "config.json" }
$LegacyConfigFile = Join-Path $LauncherRoot "config.json"
$IconFile = Join-Path $LauncherRoot "assets\app.ico"
$VbsScript = Join-Path $LauncherRoot "scripts\launch.vbs"

if (-not $Quiet) {
    if ((Get-LauncherLanguage) -eq "zh") {
        Write-Host "DeepSeek Harness Launcher 安装向导" -ForegroundColor Cyan
    }
    else {
        Write-Host "DeepSeek Harness Launcher setup" -ForegroundColor Cyan
    }
}

foreach ($requiredFile in @($DefaultConfigFile, $VbsScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) { throw "Missing required file: $requiredFile" }
}
if (-not (Test-Path -LiteralPath $IconFile -PathType Leaf)) {
    $buildScript = Join-Path $PSScriptRoot "build_icon.py"
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python -or -not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
        throw "The icon is missing and cannot be rebuilt: $IconFile"
    }
    & $python.Source $buildScript
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $IconFile -PathType Leaf)) { throw "Icon generation failed." }
}

$defaults = Get-Content -LiteralPath $DefaultConfigFile -Raw -Encoding utf8 | ConvertFrom-Json
$config = [ordered]@{
    schemaVersion = 1
    mode = [string]$defaults.mode
    projectPath = [string]$defaults.projectPath
    packageVersion = [string]$defaults.packageVersion
    extraArgs = @($defaults.extraArgs)
    port = [int]$defaults.port
    host = [string]$defaults.host
    autoOpenBrowser = [bool]$defaults.autoOpenBrowser
    timeoutSeconds = [int]$defaults.timeoutSeconds
}

$existingFile = $null
if (Test-Path -LiteralPath $TargetConfigFile -PathType Leaf) { $existingFile = $TargetConfigFile }
elseif (Test-Path -LiteralPath $LegacyConfigFile -PathType Leaf) { $existingFile = $LegacyConfigFile }
if ($existingFile) {
    try {
        $existing = Get-Content -LiteralPath $existingFile -Raw -Encoding utf8 | ConvertFrom-Json
        foreach ($key in @("mode", "projectPath", "packageVersion", "extraArgs", "port", "host", "autoOpenBrowser", "timeoutSeconds")) {
            if ($null -ne $existing.$key) { $config[$key] = $existing.$key }
        }
        if (-not $existing.mode) {
            $config.mode = if ($existing.projectPath) { "source" } else { "npm" }
        }
    }
    catch { throw "Invalid existing launcher configuration '$existingFile': $($_.Exception.Message)" }
}

if ($Mode) { $config.mode = $Mode }
if ($ProjectPath) {
    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) { throw "DeepSeek Harness project path does not exist: $ProjectPath" }
    $config.mode = "source"
    $config.projectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
}
if ($PackageVersion) { $config.packageVersion = $PackageVersion }

$config.mode = ([string]$config.mode).ToLowerInvariant()
if ($config.mode -notin @("npm", "source")) { throw "Mode must be 'npm' or 'source'." }
if ([string]$config.packageVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "packageVersion must be an exact semantic version."
}

$node = Get-NodeCompatibility
if (-not $node.Found) { throw (Get-LauncherText "NodeMissing") }
if (-not $node.Supported) {
    $displayVersion = if ($node.Version) { $node.Version.ToString() } else { "unknown" }
    throw (Get-LauncherText "NodeUnsupported" @($displayVersion))
}

if ($config.mode -eq "source") {
    $sourcePath = [string]$config.projectPath
    if (-not $sourcePath -or -not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw (Get-LauncherText "SourcePathMissing")
    }
    $packageFile = Join-Path $sourcePath "package.json"
    try {
        $package = Get-Content -LiteralPath $packageFile -Raw -Encoding utf8 | ConvertFrom-Json
        if (-not $package.scripts.dsh) { throw "package.json does not define scripts.dsh" }
    }
    catch { throw "The selected directory is not a valid DeepSeek Harness checkout: $($_.Exception.Message)" }
    if (-not (Get-Command pnpm.cmd -ErrorAction SilentlyContinue) -and -not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
        throw (Get-LauncherText "ToolMissing" @("pnpm", "source"))
    }
    $config.projectPath = (Resolve-Path -LiteralPath $sourcePath).Path
}
else {
    if (-not (Get-Command npx.cmd -ErrorAction SilentlyContinue) -and -not (Get-Command npx -ErrorAction SilentlyContinue)) {
        throw (Get-LauncherText "ToolMissing" @("npx", "npm"))
    }
    $config.projectPath = ""
}

$configParent = Split-Path -Parent $TargetConfigFile
if ($configParent) { New-Item -ItemType Directory -Path $configParent -Force | Out-Null }
$config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $TargetConfigFile -Encoding utf8

if (-not $DesktopPath) { $DesktopPath = [System.Environment]::GetFolderPath("Desktop") }
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
$shortcut.Description = "Unofficial DeepSeek Harness Web UI launcher"
$shortcut.IconLocation = "$IconFile,0"
$shortcut.Save()

Write-Host "[OK] Configuration: $TargetConfigFile" -ForegroundColor Green
Write-Host "[OK] Desktop shortcut: $shortcutPath" -ForegroundColor Green
Write-Host "[OK] Mode: $($config.mode)" -ForegroundColor Green
if ($config.mode -eq "npm") { Write-Host "[OK] Package: @deepseek-ai/dsh@$($config.packageVersion)" -ForegroundColor Green }

if (-not $Quiet) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        (Get-LauncherText "Installed" @($shortcutPath, $TargetConfigFile)),
        (Get-LauncherText "InstalledTitle"),
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}
