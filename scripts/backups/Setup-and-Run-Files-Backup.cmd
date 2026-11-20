@echo off
setlocal DisableDelayedExpansion
set "STROKED_FILES_SOURCE_FOLDER=%~dp0"
if not defined STROKED_FILES_INSTALL_DIR set "STROKED_FILES_INSTALL_DIR=%LOCALAPPDATA%\StrokedBackup\tools"
echo Stroked image and source backup setup
echo Keep Docker Desktop running. No passwords need to be pasted here.
echo Checking and installing the files backup helpers...
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; $src=$env:STROKED_FILES_SOURCE_FOLDER; $folder=$env:STROKED_FILES_INSTALL_DIR; $null=New-Item -ItemType Directory -Path $folder -Force; $p=Join-Path $src 'Stroked-Database-Backup.ps1'; if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne 'f20374c29a5abfde86fe8d417da2b279300aac0b5a63b863274bff739b37e27c') {throw 'A bundled helper failed its integrity check.'}; Unblock-File -LiteralPath $p; Copy-Item -LiteralPath $p -Destination (Join-Path $folder 'Stroked-Database-Backup.ps1') -Force; if ((Get-FileHash -LiteralPath (Join-Path $folder 'Stroked-Database-Backup.ps1') -Algorithm SHA256).Hash -ne 'f20374c29a5abfde86fe8d417da2b279300aac0b5a63b863274bff739b37e27c') {throw 'An installed helper failed its integrity check.'}; $p=Join-Path $src 'Stroked-Files-Backup.ps1'; if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne 'a41513201fe9feb45d560ecfc0ac97c8e8498f9faeb5cd97403dc5704dc3d521') {throw 'A bundled helper failed its integrity check.'}; Unblock-File -LiteralPath $p; Copy-Item -LiteralPath $p -Destination (Join-Path $folder 'Stroked-Files-Backup.ps1') -Force; if ((Get-FileHash -LiteralPath (Join-Path $folder 'Stroked-Files-Backup.ps1') -Algorithm SHA256).Hash -ne 'a41513201fe9feb45d560ecfc0ac97c8e8498f9faeb5cd97403dc5704dc3d521') {throw 'An installed helper failed its integrity check.'}"
if errorlevel 1 goto setup_failed
if /I "%~1"=="--install-only" goto install_only
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%STROKED_FILES_INSTALL_DIR%\Stroked-Files-Backup.ps1"
set "STROKED_FILES_EXIT=%ERRORLEVEL%"
if not "%STROKED_FILES_EXIT%"=="0" goto backup_failed
echo.
echo The files archive step finished. Leave this window open for review.
echo OneDrive upload, provider exports and a full restore still need checking.
pause
exit /b 0
:install_only
echo Files helpers installed. No backup was started.
exit /b 0
:setup_failed
echo Setup stopped. The backup was not started. Share the error above with ChatGPT.
pause
exit /b 1
:backup_failed
echo The files backup stopped. Leave this window open and share its final error message.
pause
exit /b %STROKED_FILES_EXIT%
