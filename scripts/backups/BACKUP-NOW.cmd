@echo off
setlocal DisableDelayedExpansion
set "STROKED_TOOLS_SOURCE=%~dp0"
if not defined STROKED_TOOLS_INSTALL set "STROKED_TOOLS_INSTALL=%LOCALAPPDATA%\StrokedBackup\tools"
echo Stroked fresh database and files backup
echo Keep Docker Desktop running. No password needs to be pasted here.
if not exist "%STROKED_TOOLS_SOURCE%Stroked-Database-Backup.ps1" goto extract_first
if not exist "%STROKED_TOOLS_SOURCE%Stroked-Recovery-Check.ps1" goto extract_first
if not exist "%STROKED_TOOLS_SOURCE%Stroked-Files-Backup.ps1" goto extract_first
if not exist "%STROKED_TOOLS_SOURCE%Stroked-Postgres-Restore-Check.ps1" goto extract_first
if not exist "%STROKED_TOOLS_SOURCE%Stroked-Run-Fresh-Backup.ps1" goto extract_first
if not exist "%STROKED_TOOLS_SOURCE%start-isolated-postgres.sh" goto extract_first
if not exist "%STROKED_TOOLS_SOURCE%verify-restored-database.sql" goto extract_first
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; $src=$env:STROKED_TOOLS_SOURCE; $dst=$env:STROKED_TOOLS_INSTALL; $null=New-Item -ItemType Directory -Path $dst -Force; $p=Join-Path $src 'Stroked-Database-Backup.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne 'f20374c29a5abfde86fe8d417da2b279300aac0b5a63b863274bff739b37e27c') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'Stroked-Database-Backup.ps1'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne 'f20374c29a5abfde86fe8d417da2b279300aac0b5a63b863274bff739b37e27c') {throw 'Installed helper integrity check failed.'}; $p=Join-Path $src 'Stroked-Recovery-Check.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne 'f3a89a16a7c7ecc14410c65f205474f93d193f4c39e3f28eb1eaa0922822a857') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'Stroked-Recovery-Check.ps1'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne 'f3a89a16a7c7ecc14410c65f205474f93d193f4c39e3f28eb1eaa0922822a857') {throw 'Installed helper integrity check failed.'}; $p=Join-Path $src 'Stroked-Files-Backup.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne '0d23a6fa7c76031811e5515da288b798295add81ec614219c8d74d4bbc0fd5d2') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'Stroked-Files-Backup.ps1'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne '0d23a6fa7c76031811e5515da288b798295add81ec614219c8d74d4bbc0fd5d2') {throw 'Installed helper integrity check failed.'}; $p=Join-Path $src 'Stroked-Postgres-Restore-Check.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne '3d16ff13259ffb6715410bb765f0b8e2703d742962917fa33e5e08ed91400495') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'Stroked-Postgres-Restore-Check.ps1'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne '3d16ff13259ffb6715410bb765f0b8e2703d742962917fa33e5e08ed91400495') {throw 'Installed helper integrity check failed.'}; $p=Join-Path $src 'Stroked-Run-Fresh-Backup.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne '8865bb1103f043ee3cbac6c50553a7a8d3d7e594b539e39300c280215c365103') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'Stroked-Run-Fresh-Backup.ps1'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne '8865bb1103f043ee3cbac6c50553a7a8d3d7e594b539e39300c280215c365103') {throw 'Installed helper integrity check failed.'}; $p=Join-Path $src 'start-isolated-postgres.sh'; if ((Get-FileHash -LiteralPath $p).Hash -ne '9218c44bed160fc6c41dbaaf52a7e49752a2a9a0fc6af1d5351ac95f0ee00628') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'start-isolated-postgres.sh'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne '9218c44bed160fc6c41dbaaf52a7e49752a2a9a0fc6af1d5351ac95f0ee00628') {throw 'Installed helper integrity check failed.'}; $p=Join-Path $src 'verify-restored-database.sql'; if ((Get-FileHash -LiteralPath $p).Hash -ne '7622130360e9255a803af154d0e4cbe57f13f5075b0eca9b87017e2e266fd98e') {throw 'Bundled helper integrity check failed.'}; Unblock-File -LiteralPath $p; $out=Join-Path $dst 'verify-restored-database.sql'; Copy-Item -LiteralPath $p -Destination $out -Force; if ((Get-FileHash -LiteralPath $out).Hash -ne '7622130360e9255a803af154d0e4cbe57f13f5075b0eca9b87017e2e266fd98e') {throw 'Installed helper integrity check failed.'}"
if errorlevel 1 goto setup_failed
if /I "%~1"=="--install-only" exit /b 0
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%STROKED_TOOLS_INSTALL%\Stroked-Run-Fresh-Backup.ps1"
set "STROKED_TOOLS_EXIT=%ERRORLEVEL%"
echo.
echo Leave this final result open for review.
pause
exit /b %STROKED_TOOLS_EXIT%
:setup_failed
echo Setup stopped before starting the operation. Share the error above.
pause
exit /b 1
:extract_first
echo Close this window and choose Extract All on the ZIP first.
echo Then open the starter from the extracted folder with all its helper files.
pause
exit /b 1
