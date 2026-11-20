@echo off
setlocal DisableDelayedExpansion
set "STROKED_BACKUP_SOURCE=%~dp0Stroked-Database-Backup.ps1"
if not defined STROKED_BACKUP_INSTALL_DIR set "STROKED_BACKUP_INSTALL_DIR=%LOCALAPPDATA%\StrokedBackup\tools"

echo Stroked database backup setup
echo Keep Docker Desktop running. No password needs to be pasted here.
echo Checking and installing the backup helper...

powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; $src=$env:STROKED_BACKUP_SOURCE; $hash='f20374c29a5abfde86fe8d417da2b279300aac0b5a63b863274bff739b37e27c'; if ((Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash -ne $hash) {throw 'The bundled script failed its integrity check.'}; Unblock-File -LiteralPath $src; $folder=$env:STROKED_BACKUP_INSTALL_DIR; $null=New-Item -ItemType Directory -Path $folder -Force; $target=Join-Path $folder 'Stroked-Database-Backup.ps1'; Copy-Item -LiteralPath $src -Destination $target -Force; if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash) {throw 'The installed helper failed its integrity check.'}"
if errorlevel 1 goto setup_failed

if /I "%~1"=="--install-only" goto install_only
echo Starting the database archive using your completed first exports...
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%STROKED_BACKUP_INSTALL_DIR%\Stroked-Database-Backup.ps1" -UseExistingExports
set "STROKED_BACKUP_EXIT=%ERRORLEVEL%"
if not "%STROKED_BACKUP_EXIT%"=="0" goto backup_failed
echo.
echo The database archive step finished. Leave this window open for review.
echo OneDrive upload, images, source and a full restore still need checking.
pause
exit /b 0

:install_only
echo Helper installed. No backup was started.
exit /b 0

:setup_failed
echo.
echo Setup stopped. The backup was not started. Share the error above with ChatGPT.
pause
exit /b 1

:backup_failed
echo.
echo The backup stopped. Leave this window open and share its final error message.
pause
exit /b %STROKED_BACKUP_EXIT%
