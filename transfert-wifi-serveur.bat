@echo off
chcp 65001 >nul
echo.
echo  ╔══════════════════════════════════════╗
echo  ║     MIGRATIX — TRANSFERT WiFi        ║
echo  ║         PC SOURCE (ancien)           ║
echo  ╚══════════════════════════════════════╝
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\wifi-serveur.ps1"
pause
