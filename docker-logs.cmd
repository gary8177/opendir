@echo off
rem Docker: follow container logs (Ctrl+C to quit)
setlocal
cd /d "%~dp0"
docker compose logs -f --tail=120
endlocal
