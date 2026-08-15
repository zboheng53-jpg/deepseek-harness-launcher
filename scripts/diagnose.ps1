param(
    [string]$ConfigPath = "",
    [string]$DataPath = "",
    [int]$TailLines = 40
)

$ErrorActionPreference = "Continue"
$LauncherRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "common.ps1")
$DataDirectory = Get-LauncherDataDirectory -DataPath $DataPath
$ConfigFile = if ($ConfigPath) { $ConfigPath } else { Join-Path $DataDirectory "config.json" }
$CompatibilityFile = Join-Path $LauncherRoot "compatibility.json"
$StateFile = Join-Path $DataDirectory "server-state.json"
$LauncherLog = Join-Path $DataDirectory "launcher.log"
$ServerLog = Join-Path $DataDirectory "server.log"

function Write-Section { param([string]$Name) Write-Output "`n=== $Name ===" }
function Get-CommandPath { param([string]$Name) $command = Get-Command $Name -ErrorAction SilentlyContinue; if ($command) { $command.Source } else { "not found" } }

Write-Output "DeepSeek Harness Launcher diagnostics"
Write-Output "Generated: $([DateTime]::UtcNow.ToString('o'))"
Write-Output "Launcher: $LauncherRoot"
Write-Output "User data: $DataDirectory"

Write-Section "System"
Write-Output "Windows: $([System.Environment]::OSVersion.VersionString)"
Write-Output "PowerShell: $($PSVersionTable.PSVersion)"
$node = Get-NodeCompatibility
Write-Output "Node: $(if ($node.Version) { $node.Version } else { 'not found or unreadable' })"
Write-Output "Node supported: $($node.Supported)"
Write-Output "node path: $(Get-CommandPath 'node.exe')"
Write-Output "npx path: $(Get-CommandPath 'npx.cmd')"
Write-Output "pnpm path: $(Get-CommandPath 'pnpm.cmd')"

Write-Section "Compatibility"
if (Test-Path -LiteralPath $CompatibilityFile) { Get-Content -LiteralPath $CompatibilityFile -Raw -Encoding utf8 } else { "missing" }

Write-Section "Configuration"
if (Test-Path -LiteralPath $ConfigFile) { Get-Content -LiteralPath $ConfigFile -Raw -Encoding utf8 } else { "not installed: $ConfigFile" }

Write-Section "Tracked server"
if (Test-Path -LiteralPath $StateFile) { Get-Content -LiteralPath $StateFile -Raw -Encoding utf8 } else { "no state file" }

$port = 3080
try {
    if (Test-Path -LiteralPath $ConfigFile) {
        $config = Get-Content -LiteralPath $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json
        if ($config.port) { $port = [int]$config.port }
    }
}
catch {}
Write-Output "Listeners on port ${port}:"
Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table -AutoSize | Out-String | Write-Output

Write-Section "Launcher log (last $TailLines lines)"
if (Test-Path -LiteralPath $LauncherLog) { Get-Content -LiteralPath $LauncherLog -Tail $TailLines -Encoding utf8 } else { "not found" }
Write-Section "Server log (last $TailLines lines)"
if (Test-Path -LiteralPath $ServerLog) { Get-Content -LiteralPath $ServerLog -Tail $TailLines -Encoding utf8 } else { "not found" }
