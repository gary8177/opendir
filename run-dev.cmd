@echo off
rem One click: build -> sync nginx config -> start nginx -> open browser
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "NGX=%ROOT%\tools\nginx"
set "NODE=%~dp0tools\node\node.exe"
set "PORT=4080"

if not exist "%NGX%\nginx.exe" (
  echo tools\nginx\nginx.exe not found.
  pause
  exit /b 1
)

echo [1/3] Building dist/ ...
if exist "%NODE%" (
  "%NODE%" "%ROOT%\build.mjs"
) else (
  powershell -ExecutionPolicy Bypass -File "%ROOT%\build.ps1"
)
if errorlevel 1 goto fail

echo.
echo [2/3] Syncing nginx config ...
copy /Y "%ROOT%\dist\nginx.conf" "%NGX%\conf\opendir.conf" >nul
if errorlevel 1 goto fail

echo [3/3] Starting nginx ...
tasklist /FI "IMAGENAME eq nginx.exe" 2>nul | find /I "nginx.exe" >nul
if not errorlevel 1 (
  echo    stopping previous instance ...
  cd /d "%NGX%"
  nginx.exe -s stop >nul 2>nul
  timeout /t 1 >nul
)
cd /d "%NGX%"
nginx.exe -t
if errorlevel 1 goto fail
start "" nginx.exe
timeout /t 1 >nul

echo.
echo OpenDir is running:  http://127.0.0.1:%PORT%/
echo Press any key to stop nginx ...
start "" http://127.0.0.1:%PORT%/
pause >nul
cd /d "%NGX%"
nginx.exe -s stop >nul 2>nul
echo nginx stopped.
goto end

:fail
echo.
echo Something failed - see messages above. nginx log: tools\nginx\logs\error.log
pause
exit /b 1

:end
endlocal
