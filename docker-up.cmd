@echo off
rem Docker: build image (if needed) + start + open browser
setlocal
cd /d "%~dp0"
where docker >nul 2>nul
if errorlevel 1 (
  echo docker not found. Install Docker Desktop or use the portable nginx (run-dev.cmd).
  pause
  exit /b 1
)
if not exist "dist\docker\index.html" (
  echo [1/2] building page ...
  call "%~dp0build.cmd"
  if errorlevel 1 goto fail
) else (
  echo [1/2] dist/docker/index.html found, skip build
)
echo [2/2] docker compose up -d --build ...
docker compose up -d --build
if errorlevel 1 goto fail
set "PORT=8080"
if exist ".env" for /f "tokens=1,2 delims==" %%A in ('findstr /B /C:"OPENDIR_PORT_HOST=" .env') do set "PORT=%%B"
echo.
echo OpenDir is running: http://127.0.0.1:%PORT%/
echo   logs : .\docker-logs.cmd
echo   stop : .\docker-down.cmd
start "" "http://127.0.0.1:%PORT%/"
goto end
:fail
echo.
echo Failed - see messages above (docker compose logs).
pause
exit /b 1
:end
endlocal
