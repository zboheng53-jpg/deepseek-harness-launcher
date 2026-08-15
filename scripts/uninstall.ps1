# DeepSeek Harness Launcher - uninstaller
param(
    [string]$DesktopPath = "",
    [string]$DataPath = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
$DataDirectory = Get-LauncherDataDirectory -DataPath $DataPath
if (-not $DesktopPath) { $DesktopPath = [System.Environment]::GetFolderPath("Desktop") }
$shortcutPath = Join-Path $DesktopPath "DeepSeek Harness.lnk"

# Stop the tracked background server before removing the shortcut.
$stopScript = Join-Path $PSScriptRoot "stop.ps1"
if (Test-Path -LiteralPath $stopScript -PathType Leaf) {
    & (Join-Path $PSHOME "powershell.exe") -NoProfile -ExecutionPolicy Bypass -File $stopScript -DataPath $DataDirectory -Quiet
}
if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
    Remove-Item -LiteralPath $shortcutPath -Force
    Write-Host "[OK] Removed desktop shortcut: $shortcutPath" -ForegroundColor Green
}

# User data is deliberately preserved so uninstalling or updating never destroys
# configuration and diagnostic history.
if (-not $Quiet) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        (Get-LauncherText "Uninstalled" @($DataDirectory)),
        (Get-LauncherText "UninstalledTitle"),
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}
