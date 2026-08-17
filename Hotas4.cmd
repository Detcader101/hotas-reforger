@echo off
rem Double-click launcher. Opens the menu; every mode is reachable from there.
rem For a specific mode from a shell:  powershell -ExecutionPolicy Bypass -File .\Hotas4.ps1 -Identify
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Hotas4.ps1" %*
if errorlevel 1 pause
