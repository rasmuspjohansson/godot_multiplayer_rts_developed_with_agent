# Join a remote game server as a human client (Windows).
# Usage:
#   .\connect_remote.ps1 -ServerIp 91.99.144.8
#   .\connect_remote.ps1 -ServerIp 91.99.144.8 -Name Human

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ServerIp,

    [Parameter(Position = 1)]
    [string]$Name = "Human"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$GamePath = Join-Path $RepoRoot "game_assets"
$Bundled = Join-Path $RepoRoot "tools\godot\Godot_v4.6.1-stable_win64.exe"

$Godot = $null
if (Test-Path $Bundled) {
    $Godot = $Bundled
} elseif ($env:GODOT_BIN) {
    $Godot = $env:GODOT_BIN
} else {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { $Godot = $cmd.Source }
}

if (-not $Godot -or -not (Test-Path $Godot)) {
    Write-Host "ERROR: Godot 4.6.1 not found."
    Write-Host ""
    Write-Host "Run this once from the project folder:"
    Write-Host "  .\install_godot_windows.bat"
    Write-Host ""
    Write-Host "Or set GODOT_BIN to your Godot executable path."
    exit 1
}

Write-Host "Using Godot: $Godot"
Write-Host "Connecting as '$Name' to ${ServerIp}:8910 ..."
Write-Host "In the lobby: press Ready when you are set."
Write-Host ""

& $Godot --path $GamePath -- --client "--name=$Name" --color=1 "--host=$ServerIp"
exit $LASTEXITCODE
