@echo off
cd /d "%~dp0tools\nginx"
nginx.exe -s stop
if errorlevel 1 (
  echo nginx is not running.
) else (
  echo nginx stopped.
)
