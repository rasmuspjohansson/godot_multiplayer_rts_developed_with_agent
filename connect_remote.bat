@echo off
setlocal EnableExtensions

REM Join a remote game server as a human client.
REM Usage: connect_remote.bat SERVER_IP [PlayerName]

set "SERVER_IP=%~1"
set "PLAYER_NAME=%~2"
if "%PLAYER_NAME%"=="" set "PLAYER_NAME=Human"

if "%SERVER_IP%"=="" (
  echo Usage: connect_remote.bat SERVER_IP [PlayerName]
  echo Example: connect_remote.bat 91.99.144.8
  echo.
  echo If Godot is not installed yet, run install_godot_windows.bat first.
  exit /b 1
)

set "REPO=%~dp0"
set "GODOT_BUNDLED=%REPO%tools\godot\Godot_v4.6.1-stable_win64.exe"
set "GODOT="

if exist "%GODOT_BUNDLED%" (
  set "GODOT=%GODOT_BUNDLED%"
) else if defined GODOT_BIN (
  set "GODOT=%GODOT_BIN%"
) else (
  where godot >nul 2>nul
  if not errorlevel 1 (
    for /f "delims=" %%i in ('where godot') do (
      set "GODOT=%%i"
      goto :found
    )
  )
)

:found
if not defined GODOT (
  echo ERROR: Godot 4.6.1 not found.
  echo.
  echo Run this once from the project folder:
  echo   install_godot_windows.bat
  echo.
  echo Or set GODOT_BIN to your Godot executable path.
  exit /b 1
)

if not exist "%GODOT%" (
  echo ERROR: Godot path does not exist: %GODOT%
  echo Run install_godot_windows.bat first.
  exit /b 1
)

echo Using Godot: %GODOT%
echo Connecting as '%PLAYER_NAME%' to %SERVER_IP%:8910 ...
echo In the lobby: press Ready when you are set.
echo.

"%GODOT%" --path "%REPO%game_assets" -- --client --name=%PLAYER_NAME% --color=1 --host=%SERVER_IP%
exit /b %ERRORLEVEL%
