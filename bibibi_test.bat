@echo off
rem ============================================================
rem  bibibi_test - laptop hardware test (Windows 10 / 11)
rem  https://github.com/w00o-o00w/bibibi_test
rem  Double-click: asks for admin rights and runs the test.
rem  If bibibi_test.ps1 is not next to this file, it is downloaded
rem  from GitHub into TEMP and deleted after the test.
rem ============================================================
setlocal
title bibibi_test

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

cd /d "%~dp0"
set "PS1=%~dp0bibibi_test.ps1"
set "DL=0"
if exist "%PS1%" goto run

set "PS1=%TEMP%\bibibi_test.ps1"
set "DL=1"
echo Downloading bibibi_test.ps1 from GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/w00o-o00w/bibibi_test/main/bibibi_test.ps1' -OutFile (Join-Path $env:TEMP 'bibibi_test.ps1')"
if not exist "%PS1%" (
  echo.
  echo Download failed. Check the internet connection or put bibibi_test.ps1 next to this file.
  pause
  exit /b 1
)

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
if "%DL%"=="1" del /q "%PS1%" >nul 2>&1
echo.
pause
