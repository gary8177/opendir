@echo off
rem Docker: stop and remove container
setlocal
cd /d "%~dp0"
docker compose down
echo docker compose down done.
endlocal
