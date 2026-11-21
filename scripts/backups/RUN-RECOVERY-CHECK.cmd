@echo off
setlocal DisableDelayedExpansion
set "STROKED_RECOVERY_SOURCE=%~dp0"
set "STROKED_RECOVERY_TOOLS=%LOCALAPPDATA%\StrokedBackup\tools"
if not exist "%STROKED_RECOVERY_SOURCE%Stroked-Database-Backup.ps1" goto extract_first
if not exist "%STROKED_RECOVERY_SOURCE%Stroked-Recovery-Check.ps1" goto extract_first
echo Checking recovery from the downloaded OneDrive ZIP.
echo Have the backup-recovery password from Edge Password Manager ready.
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; $src=$env:STROKED_RECOVERY_SOURCE; $folder=$env:STROKED_RECOVERY_TOOLS; $null=New-Item -ItemType Directory -Path $folder -Force; $p=Join-Path $src 'Stroked-Database-Backup.ps1'; if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne 'f20374c29a5abfde86fe8d417da2b279300aac0b5a63b863274bff739b37e27c') {throw 'Recovery helper integrity check failed.'}; Unblock-File -LiteralPath $p; Copy-Item -LiteralPath $p -Destination (Join-Path $folder 'Stroked-Database-Backup.ps1') -Force; $p=Join-Path $src 'Stroked-Recovery-Check.ps1'; if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne 'f3a89a16a7c7ecc14410c65f205474f93d193f4c39e3f28eb1eaa0922822a857') {throw 'Recovery helper integrity check failed.'}; Unblock-File -LiteralPath $p; Copy-Item -LiteralPath $p -Destination (Join-Path $folder 'Stroked-Recovery-Check.ps1') -Force"
if errorlevel 1 goto failed
powershell.exe -STA -NoProfile -ExecutionPolicy RemoteSigned -File "%STROKED_RECOVERY_TOOLS%\Stroked-Recovery-Check.ps1"
set "STROKED_RECOVERY_EXIT=%ERRORLEVEL%"
if not "%STROKED_RECOVERY_EXIT%"=="0" goto failed
echo Leave the final result open for review.
pause
exit /b 0
:extract_first
echo Choose Extract All on this checker ZIP first, then run the starter from the extracted folder.
pause
exit /b 1
:failed
echo The recovery check did not pass. Leave the final error open for review.
pause
exit /b 1
