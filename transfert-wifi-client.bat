@echo off
chcp 65001 >nul
echo.
echo  ╔══════════════════════════════════════╗
echo  ║     MIGUATION — TRANSFERT WiFi        ║
echo  ║        PC DESTINATION (nouveau)      ║
echo  ╚══════════════════════════════════════╝
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\wifi-client.ps1"
pause
