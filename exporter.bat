@echo off
chcp 65001 >nul
echo.
echo  ╔══════════════════════════════════════╗
echo  ║         MIGUATION — EXPORTATION       ║
echo  ╚══════════════════════════════════════╝
echo.
echo  Ce script va copier tes fichiers et parametres
echo  vers le dossier de destination de ton choix.
echo.
set /p DEST="Ou veux-tu sauvegarder ? (ex: E:\migration) : "
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\export.ps1" -Destination "%DEST%"
echo.
pause
