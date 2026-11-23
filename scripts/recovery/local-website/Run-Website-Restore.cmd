@echo off
setlocal
rem Process-only execution-policy override; machine policy stays unchanged.
rem Keep the PowerShell window open after completion or a startup error.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File "%~dp0Restore-Local-Website.ps1"
echo.
pause
