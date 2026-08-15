param(
    [Parameter(Mandatory = $true)][string]$DescriptorPath
)

$ErrorActionPreference = "Stop"
$descriptor = $null
try {
    $descriptor = Get-Content -LiteralPath $DescriptorPath -Raw -Encoding utf8 | ConvertFrom-Json
    if (-not $descriptor.executable -or -not $descriptor.workingDirectory -or -not $descriptor.logFile) {
        throw "The server launch descriptor is incomplete."
    }
    Set-Location -LiteralPath ([string]$descriptor.workingDirectory)
    $arguments = @($descriptor.arguments | ForEach-Object { [string]$_ })
    & ([string]$descriptor.executable) @arguments *>> ([string]$descriptor.logFile)
    if ($null -eq $LASTEXITCODE) { exit 0 }
    exit $LASTEXITCODE
}
catch {
    $message = "Server runner failed: $($_ | Out-String)"
    if ($descriptor -and $descriptor.logFile) {
        Add-Content -LiteralPath ([string]$descriptor.logFile) -Value $message -Encoding utf8 -ErrorAction SilentlyContinue
    }
    exit 1
}
