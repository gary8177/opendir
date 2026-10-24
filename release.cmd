@echo off
rem Pack release/OpenDir-<version>.zip
cd /d "%~dp0"
set "NODE=%~dp0tools\node\node.exe"
if exist "%NODE%" (
  "%NODE%" "%~dp0release.mjs"
) else (
  echo Node not found: install Node or keep tools\node\ in place.
)
