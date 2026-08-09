# Download Godot 4.6.1 (Windows) into tools/godot/ so connect_remote.bat can find it.
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\install_godot_windows.ps1
#   powershell -ExecutionPolicy Bypass -File .\install_godot_windows.ps1 -Force

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$GodotVersion = "4.6.1-stable"
$ExeName = "Godot_v4.6.1-stable_win64.exe"
# Official asset name includes ".exe" before ".zip" (Godot_vX.Y.Z-stable_win64.exe.zip).
$ZipName = "Godot_v4.6.1-stable_win64.exe.zip"
$DownloadUrl = "https://github.com/godotengine/godot-builds/releases/download/$GodotVersion/$ZipName"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolsDir = Join-Path $RepoRoot "tools\godot"
$ExePath = Join-Path $ToolsDir $ExeName
$ZipPath = Join-Path $ToolsDir $ZipName

Write-Host "Godot Windows installer"
Write-Host "  Target: $ExePath"
Write-Host ""

if ((Test-Path $ExePath) -and -not $Force) {
    Write-Host "Already installed. Use -Force to re-download."
    Write-Host ""
    Write-Host "Next step:"
    Write-Host "  connect_remote.bat SERVER_IP"
    exit 0
}

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

Write-Host "Checking download URL ..."
try {
    $head = Invoke-WebRequest -Uri $DownloadUrl -Method Head -UseBasicParsing
    if ($head.StatusCode -lt 200 -or $head.StatusCode -ge 400) {
        throw "HTTP $($head.StatusCode)"
    }
} catch {
    Write-Error "Download URL not reachable: $DownloadUrl`n$($_.Exception.Message)"
    exit 1
}

Write-Host "Downloading $DownloadUrl ..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing

if (-not (Test-Path $ZipPath) -or (Get-Item $ZipPath).Length -lt 1MB) {
    Write-Error "Download failed or file too small: $ZipPath"
    exit 1
}

Write-Host "Extracting to $ToolsDir ..."
Expand-Archive -Path $ZipPath -DestinationPath $ToolsDir -Force
Remove-Item -Force $ZipPath

if (-not (Test-Path $ExePath)) {
    # Some zips nest the exe; find it and move into place.
    $found = Get-ChildItem -Path $ToolsDir -Filter $ExeName -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $found) {
        Write-Error "Download finished but $ExeName was not found under $ToolsDir"
        exit 1
    }
    if ($found.FullName -ne $ExePath) {
        Move-Item -Force $found.FullName $ExePath
    }
}

Write-Host ""
Write-Host "Godot 4.6.1 installed successfully."
Write-Host ""
Write-Host "Next step (join a remote game):"
Write-Host "  connect_remote.bat SERVER_IP"
Write-Host "Then press Ready in the lobby."
