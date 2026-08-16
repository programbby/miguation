@echo off
chcp 65001 >nul
echo.
echo  ╔══════════════════════════════════════╗
echo  ║         MIGRATIX — IMPORTATION       ║
echo  ╚══════════════════════════════════════╝
echo.
echo  Ce script va restaurer tes fichiers sur ce nouveau PC.
echo.
set /p SOURCE="Ou se trouve ta sauvegarde ? (ex: E:\migration) : "
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\import.ps1" -Source "%SOURCE%"
echo.
pause
