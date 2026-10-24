@echo off
rem Interactive setup for the Docker deployment (writes .env)
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0init-docker.ps1" %*
if errorlevel 1 pause
