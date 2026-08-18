#!/bin/bash

# Détection OS
OS="$(uname -s)"
case "$OS" in
    Linux*)  SYSTEME="linux" ;;
    Darwin*) SYSTEME="mac" ;;
    *)       echo "Système non supporté : $OS"; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo " ╔══════════════════════════════════════╗"
echo " ║            MIGUATION                  ║"
echo " ╚══════════════════════════════════════╝"
echo ""
echo " Système détecté : $OS"
echo ""
echo " Que veux-tu faire ?"
echo "   1) Exporter (cet ordi → clé USB ou dossier)"
echo "   2) Importer (dossier → cet ordi)"
echo "   3) Transférer via WiFi (serveur — cet ordi envoie)"
echo "   4) Transférer via WiFi (client — cet ordi reçoit)"
echo ""
read -p " Ton choix (1/2/3/4) : " CHOIX

case "$CHOIX" in
    1) bash "$SCRIPT_DIR/scripts/export.sh" ;;
    2) bash "$SCRIPT_DIR/scripts/import.sh" ;;
    3) bash "$SCRIPT_DIR/scripts/wifi-serveur.sh" "$SYSTEME" ;;
    4) bash "$SCRIPT_DIR/scripts/wifi-client.sh" ;;
    *) echo "Choix invalide."; exit 1 ;;
esac
