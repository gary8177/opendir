@echo off
rem Upload release\OpenDir-*-docker.zip to a Linux server and unzip it there.
rem usage: deploy-docker.cmd user@host [remote_dir]
setlocal
cd /d "%~dp0"
set "TARGET=%~1"
set "RDIR=%~2"
if "%TARGET%"=="" goto usage
if "%RDIR%"=="" set "RDIR=/opt"
if not exist "release" (
  echo release\ not found - run release.cmd first.
  pause
  exit /b 1
)
set "ZIP="
for %%F in (release\OpenDir-*-docker.zip) do set "ZIP=%%~nxF"
if "%ZIP%"=="" (
  echo No OpenDir-*-docker.zip in release\ - run release.cmd first.
  pause
  exit /b 1
)
set "BUNDLE=%ZIP:-docker.zip=%"
where scp >nul 2>nul
if errorlevel 1 (
  echo scp not found. Enable "OpenSSH Client" in Windows optional features.
  pause
  exit /b 1
)
echo [1/2] scp release\%ZIP% -^> %TARGET%:/tmp/
scp -o StrictHostKeyChecking=accept-new "release\%ZIP%" "%TARGET%:/tmp/"
if errorlevel 1 goto fail
echo.
echo [2/2] unzip on server ...
ssh -o StrictHostKeyChecking=accept-new "%TARGET%" "set -e; mkdir -p %RDIR%; cd %RDIR%; unzip -o -q /tmp/%ZIP%; echo ---; ls -1 %BUNDLE%"
if errorlevel 1 goto fail
echo.
echo Done. Now on the server:
echo   cd %RDIR%/%BUNDLE%
echo   sh init-docker.sh          ^(or: cp .env.example .env ^&^& edit^)
echo   docker compose up -d --build
echo   docker compose logs -f
goto end
:usage
echo usage: deploy-docker.cmd user@host [remote_dir]
echo   example: deploy-docker.cmd root@your-server /opt
goto end
:fail
echo.
echo FAILED - check: ssh works? unzip installed? remote dir writable?
pause
:end
endlocal
