@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
endlocal