@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Export-NetworkSettings.ps1"
set "exportResult=%errorlevel%"
echo.
if "%exportResult%"=="0" (echo Export completed.) else (echo Export returned code %exportResult%. Check the output above.)
pause
exit /b %exportResult%
