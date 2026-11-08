@echo off
rem Double-click: close the Funnel and stop the home server.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0home-server.ps1" stop
pause
