@echo off
setlocal
title Windows Vista x64 certificate installer
pushd "%~dp0"

echo Windows Vista x64 Certificates Installer
echo =========================================
echo.
echo This imports the supplied Microsoft trusted-root store into the
echo Local Computer certificate store. It does not install Windows updates,
echo Java, a launcher, Minecraft, or One-Core-API.
echo.

if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" goto architecture_ok
if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" goto architecture_ok
echo ERROR: This package is only for 64-bit Windows Vista.
goto failed

:architecture_ok
cacls.exe "%SystemRoot%\system32\config\system" >nul 2>&1
if errorlevel 1 (
  echo ERROR: Administrator access is required.
  echo Right-click this BAT and choose Run as administrator, then try again.
  goto failed
)

if not exist "%~dp0WURoots.sst" (
  echo ERROR: WURoots.sst is missing from this folder.
  goto failed
)

if not exist "%~dp0import-sst-vista-x64.exe" (
  echo ERROR: import-sst-vista-x64.exe is missing from this folder.
  goto failed
)

echo Importing the Microsoft trusted-root store...
"%~dp0import-sst-vista-x64.exe" "%~dp0WURoots.sst" ROOT > "%~dp0certificate-install.log" 2>&1
if errorlevel 1 (
  echo.
  echo ERROR: Certificate import failed. Details:
  type "%~dp0certificate-install.log"
  goto failed
)

echo.
type "%~dp0certificate-install.log"
echo.
echo SUCCESS: The trusted-root store was imported.
echo Restart Windows Vista before signing in or downloading Minecraft.
echo Also make sure the computer's date, time, and time zone are correct.
echo.
pause
popd
exit /b 0

:failed
echo.
echo Read README.txt for help. No Java, launcher, Minecraft, account, or world
echo files were changed.
echo.
pause
popd
exit /b 1

