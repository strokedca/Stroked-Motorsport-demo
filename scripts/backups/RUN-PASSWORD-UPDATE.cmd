@echo off
setlocal DisableDelayedExpansion
set "STROKED_PASSWORD_SOURCE=%~dp0"
set "STROKED_PASSWORD_TOOLS=%LOCALAPPDATA%\StrokedBackup\tools"
if not exist "%STROKED_PASSWORD_SOURCE%Stroked-Database-Backup.ps1" goto extract_first
if not exist "%STROKED_PASSWORD_SOURCE%Stroked-Recovery-Check.ps1" goto extract_first
if not exist "%STROKED_PASSWORD_SOURCE%Stroked-Update-Recovery-Password.ps1" goto extract_first
echo Updating only the recovery-key password wrapper.
echo Keep the Edge password field hidden in any photos.
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; $src=$env:STROKED_PASSWORD_SOURCE; $folder=$env:STROKED_PASSWORD_TOOLS; $null=New-Item -ItemType Directory -Path $folder -Force; $p=Join-Path $src 'Stroked-Database-Backup.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne 'f20374c29a5abfde86fe8d417da2b279300aac0b5a63b863274bff739b37e27c') {throw 'Password updater integrity check failed.'}; Unblock-File -LiteralPath $p; Copy-Item -LiteralPath $p -Destination (Join-Path $folder 'Stroked-Database-Backup.ps1') -Force; $p=Join-Path $src 'Stroked-Recovery-Check.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne 'f3a89a16a7c7ecc14410c65f205474f93d193f4c39e3f28eb1eaa0922822a857') {throw 'Password updater integrity check failed.'}; Unblock-File -LiteralPath $p; Copy-Item -LiteralPath $p -Destination (Join-Path $folder 'Stroked-Recovery-Check.ps1') -Force; $p=Join-Path $src 'Stroked-Update-Recovery-Password.ps1'; if ((Get-FileHash -LiteralPath $p).Hash -ne '801f10d92a10c07957abd37c42fffd258a92c7b03a260aa8fb76b82d5ad5de47') {throw 'Password updater integrity check failed.'}; Unblock-File -LiteralPath $p; Copy-Item -LiteralPath $p -Destination (Join-Path $folder 'Stroked-Update-Recovery-Password.ps1') -Force"
if errorlevel 1 goto failed
powershell.exe -STA -NoProfile -ExecutionPolicy RemoteSigned -File "%STROKED_PASSWORD_TOOLS%\Stroked-Update-Recovery-Password.ps1"
set "STROKED_PASSWORD_EXIT=%ERRORLEVEL%"
if not "%STROKED_PASSWORD_EXIT%"=="0" goto failed
echo Leave the final result open for review, with the Edge password pane closed.
pause
exit /b 0
:extract_first
echo Choose Extract All on the password update ZIP first, then run the starter from its extracted folder.
pause
exit /b 1
:failed
echo The password update did not finish. Leave the final error open for review.
pause
exit /b 1
