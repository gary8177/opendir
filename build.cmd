@echo off
rem Build dist/ with bundled node (fallback: PowerShell)
cd /d "%~dp0"
set "NODE=%~dp0tools\node\node.exe"
if exist "%NODE%" (
  "%NODE%" "%~dp0build.mjs"
) else (
  powershell -ExecutionPolicy Bypass -File "%~dp0build.ps1"
)
if errorlevel 1 (
  echo.
  echo Build failed.
  pause
  exit /b 1
)
