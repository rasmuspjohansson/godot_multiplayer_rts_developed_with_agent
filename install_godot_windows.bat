@echo off
setlocal
REM One-click installer: downloads Godot 4.6.1 into tools\godot\
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_godot_windows.ps1" %*
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo Install failed with exit code %ERR%.
  pause
  exit /b %ERR%
)
echo.
pause
exit /b 0
