# Build the watch face. Usage: .\build.ps1 [-Device fr970] [-Run]
#   -Run  also launches the simulator (if needed) and loads the .prg into it.
#         monkeydo stays attached and streams the app's console output; Ctrl+C detaches.
param(
    [string]$Device = "fr970",
    [switch]$Run
)
$ErrorActionPreference = "Stop"

$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg" -Raw).Trim()
$bin = Join-Path $sdk "bin"
$key = Join-Path $env:USERPROFILE ".connectiq\developer_key.der"
$out = Join-Path $PSScriptRoot "bin\WatchFace.prg"

New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
& "$bin\monkeyc.bat" -d $Device -f (Join-Path $PSScriptRoot "monkey.jungle") -o $out -y $key -w
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Run) {
    if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) {
        Start-Process "$bin\connectiq.bat"
        Start-Sleep -Seconds 5
    }
    & "$bin\monkeydo.bat" $out $Device
}
