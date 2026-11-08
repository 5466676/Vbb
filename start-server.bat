@echo off
rem Double-click: start the home server and open the Tailscale Funnel.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0home-server.ps1" start
pause
