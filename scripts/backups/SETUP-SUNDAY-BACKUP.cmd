@echo off
setlocal DisableDelayedExpansion
set "STROKED_SUNDAY_SOURCE=%~dp0"
if not defined STROKED_SUNDAY_INSTALL set "STROKED_SUNDAY_INSTALL=%LOCALAPPDATA%\StrokedBackup\tools"
echo Stroked Sunday 9:00 AM backup setup
echo Keep the extracted helper files together. No password needs to be pasted.
if not exist "%STROKED_SUNDAY_SOURCE%Stroked-Database-Backup.ps1" goto extract_first
if not exist "%STROKED_SUNDAY_SOURCE%Stroked-Recovery-Check.ps1" goto extract_first
if not exist "%STROKED_SUNDAY_SOURCE%Stroked-Files-Backup.ps1" goto extract_first
if not exist "%STROKED_SUNDAY_SOURCE%Stroked-Run-Fresh-Backup.ps1" goto extract_first
if not exist "%STROKED_SUNDAY_SOURCE%Stroked-Sunday-Schedule.ps1" goto extract_first
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; $src=$env:STROKED_SUNDAY_SOURCE; $dst=$env:STROKED_SUNDAY_INSTALL; $null=New-Item -ItemType Directory -Path $dst -Force; $p=Join-Path $src 'Stroked-Database-Backup.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne 'f20374c29a5abfde86fe8d417da2b279300aac0b5a63b863274bff739b37e27c') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'Stroked-Database-Backup.ps1'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne 'f20374c29a5abfde86fe8d417da2b279300aac0b5a63b863274bff739b37e27c') {throw 'Installed helper integrity check failed.'}; $p=Join-Path $src 'Stroked-Recovery-Check.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne 'f3a89a16a7c7ecc14410c65f205474f93d193f4c39e3f28eb1eaa0922822a857') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'Stroked-Recovery-Check.ps1'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne 'f3a89a16a7c7ecc14410c65f205474f93d193f4c39e3f28eb1eaa0922822a857') {throw 'Installed helper integrity check failed.'}; $p=Join-Path $src 'Stroked-Files-Backup.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne '0dec8e419d3e453f9db37432f2ac0073c90dd5c362738b78f04abdcbe099d281') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'Stroked-Files-Backup.ps1'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne '0dec8e419d3e453f9db37432f2ac0073c90dd5c362738b78f04abdcbe099d281') {throw 'Installed helper integrity check failed.'}; $p=Join-Path $src 'Stroked-Run-Fresh-Backup.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne '8865bb1103f043ee3cbac6c50553a7a8d3d7e594b539e39300c280215c365103') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'Stroked-Run-Fresh-Backup.ps1'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne '8865bb1103f043ee3cbac6c50553a7a8d3d7e594b539e39300c280215c365103') {throw 'Installed helper integrity check failed.'}; $p=Join-Path $src 'Stroked-Sunday-Schedule.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne '6a1b69903fda10e5d6dd3766c17cf6233c13921d165052c0f41fd5ae7a4d9251') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'Stroked-Sunday-Schedule.ps1'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne '6a1b69903fda10e5d6dd3766c17cf6233c13921d165052c0f41fd5ae7a4d9251') {throw 'Installed helper integrity check failed.'}"
if errorlevel 1 goto setup_failed
if /I "%~1"=="--install-only" exit /b 0
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%STROKED_SUNDAY_INSTALL%\Stroked-Sunday-Schedule.ps1" -ScheduleMode Install
set "STROKED_SUNDAY_EXIT=%ERRORLEVEL%"
echo.
echo Leave this final result open for review.
pause
exit /b %STROKED_SUNDAY_EXIT%
:setup_failed
echo Setup stopped before changing the schedule. Share the error above.
pause
exit /b 1
:extract_first
echo Close this window and choose Extract All on the ZIP first.
echo Then run the starter from the extracted folder with all its helper files.
pause
exit /b 1
