@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Remote-Desktop-Commander.ps1"
endlocal
