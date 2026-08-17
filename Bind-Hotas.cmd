@echo off
REM Double-click launcher for the HOTAS binding wizard.
REM Sizes the console so the diagnostic panel fits, then hands over.
mode con: cols=82 lines=34 >nul 2>&1
title HOTAS Binding Wizard
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bind-Hotas.ps1" %*
if errorlevel 1 (
  echo.
  echo The wizard exited with an error. Press a key to close.
  pause >nul
)
