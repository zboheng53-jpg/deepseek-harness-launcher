param(
    [switch]$InstallerSmoke,
    [string]$HarnessProjectPath = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$required = @(
    "assets\app.ico",
    "assets\app.png",
    "assets\logo.svg",
    "scripts\launch.ps1",
    "scripts\launch.vbs",
    "scripts\stop.ps1",
    "scripts\install.ps1",
    "scripts\uninstall.ps1",
    "config.json",
    "install.bat",
    "stop.bat",
    "uninstall.bat",
    "README.md",
    "README.zh.md",
    "LICENSE"
)

foreach ($relative in $required) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required file: $relative"
    }
}

$parseFailures = New-Object System.Collections.Generic.List[string]
foreach ($script in Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -Filter "*.ps1" -File) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in @($errors)) {
        $parseFailures.Add("$($script.Name): $($parseError.Message)")
    }
}
if ($parseFailures.Count -gt 0) {
    throw "PowerShell parse errors:`n$($parseFailures -join "`n")"
}

$config = Get-Content -LiteralPath (Join-Path $Root "config.json") -Raw -Encoding utf8 | ConvertFrom-Json
foreach ($key in @("projectPath", "port", "host", "command", "autoOpenBrowser", "timeoutSeconds")) {
    if ($null -eq $config.$key) { throw "config.json is missing '$key'" }
}
if ([int]$config.port -lt 1 -or [int]$config.port -gt 65535) {
    throw "config.json contains an invalid port"
}

$icoBytes = [System.IO.File]::ReadAllBytes((Join-Path $Root "assets\app.ico"))
if ($icoBytes.Length -lt 22 -or $icoBytes[0] -ne 0 -or $icoBytes[1] -ne 0 -or $icoBytes[2] -ne 1 -or $icoBytes[3] -ne 0) {
    throw "assets/app.ico has an invalid ICO header"
}
$iconCount = [BitConverter]::ToUInt16($icoBytes, 4)
if ($iconCount -lt 6) {
    throw "assets/app.ico should contain at least 6 sizes; found $iconCount"
}

if ($InstallerSmoke) {
    if (-not $HarnessProjectPath) {
        throw "-HarnessProjectPath is required with -InstallerSmoke"
    }
    $smokeDesktop = Join-Path ([System.IO.Path]::GetTempPath()) ("dsh-launcher-smoke-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $smokeDesktop -Force | Out-Null
    try {
        & (Join-Path $Root "scripts\install.ps1") -ProjectPath $HarnessProjectPath -DesktopPath $smokeDesktop -Quiet
        $shortcutPath = Join-Path $smokeDesktop "DeepSeek Harness.lnk"
        if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
            throw "Installer did not create the shortcut"
        }
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        if ($shortcut.Arguments -notlike "*launch.vbs*") { throw "Shortcut arguments do not target launch.vbs" }
        if ($shortcut.IconLocation -notlike "*app.ico,0") { throw "Shortcut icon is incorrect" }
    }
    finally {
        Remove-Item -LiteralPath $smokeDesktop -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Verification passed ($iconCount icon sizes)." -ForegroundColor Green
