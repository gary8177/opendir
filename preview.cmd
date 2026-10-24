@echo off
cd /d "%~dp0"
if not exist "dist\preview.html" (
  echo dist\preview.html not found - run build.cmd first.
  pause
  exit /b 1
)
start "" "dist\preview.html"
