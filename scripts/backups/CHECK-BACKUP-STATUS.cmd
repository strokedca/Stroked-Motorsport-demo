@echo off
setlocal DisableDelayedExpansion
if not exist "%LOCALAPPDATA%\StrokedBackup\tools\Stroked-Sunday-Schedule.ps1" goto missing
powershell.exe -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%LOCALAPPDATA%\StrokedBackup\tools\Stroked-Sunday-Schedule.ps1" -ScheduleMode Status
set "STROKED_SHORTCUT_EXIT=%ERRORLEVEL%"
exit /b %STROKED_SHORTCUT_EXIT%
:missing
echo Please run SETUP-SUNDAY-BACKUP.cmd from the extracted folder first.
pause
exit /b 1
