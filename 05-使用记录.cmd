@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Usage-Tracker.ps1" -Action show
endlocal
