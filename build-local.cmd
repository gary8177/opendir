@echo off
rem Build with settings.local.json (your machine-specific paths)
cd /d "%~dp0"
set "OPENDIR_SETTINGS=settings.local.json"
set "NODE=%~dp0tools\node\node.exe"
if exist "%NODE%" (
  "%NODE%" "%~dp0build.mjs"
) else (
  powershell -ExecutionPolicy Bypass -File "%~dp0build.ps1"
)
