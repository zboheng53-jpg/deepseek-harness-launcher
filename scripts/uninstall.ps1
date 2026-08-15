# DeepSeek Harness Desktop Launcher - Uninstaller
param(
    [string]$DesktopPath = "",
    [switch]$Quiet
)

if (-not $DesktopPath) {
    $DesktopPath = [System.Environment]::GetFolderPath('Desktop')
}
$shortcutPath = Join-Path $desktopPath "DeepSeek Harness.lnk"

if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    Write-Host "[✓] 已删除桌面快捷方式: $shortcutPath" -ForegroundColor Green
}

# Stop background server if running
$stopScript = Join-Path $PSScriptRoot "stop.ps1"
if (Test-Path -LiteralPath $stopScript) {
    & powershell.exe -ExecutionPolicy Bypass -File "$stopScript" -Quiet
}

if (-not $Quiet) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "DeepSeek Harness 桌面快捷方式已成功卸载！",
        "卸载完成",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}
