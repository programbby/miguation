#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

step() { echo -e "  ${CYAN}>> $1${RESET}"; }
ok()   { echo -e "  ${GREEN}OK $1${RESET}"; }
fail() { echo -e "  ${RED}!! $1${RESET}"; }

echo ""
echo -e "  ${YELLOW}Connecte-toi d'abord au WiFi 'Miguation'.${RESET}"
echo -e "  ${YELLOW}(Le mot de passe est affiché sur l'ancien PC)${RESET}"
read -rp "  Appuie sur Entrée quand tu es connecté..."

read -rp "  Entre l'URL affichée sur l'ancien PC (http://...): " URL

if [ -z "$URL" ]; then
    fail "URL vide."
    exit 1
fi

DEST="$HOME/miguation-import"
ARCHIVE="$DEST/miguation.tar.gz"
mkdir -p "$DEST"

step "Téléchargement de l'archive..."

if command -v curl &>/dev/null; then
    curl -L --progress-bar --connect-timeout 15 --retry 3 -o "$ARCHIVE" "$URL"
elif command -v wget &>/dev/null; then
    wget --progress=bar --tries=3 --timeout=15 -O "$ARCHIVE" "$URL"
else
    fail "curl ou wget requis."
    exit 1
fi

if [ ! -f "$ARCHIVE" ] || [ ! -s "$ARCHIVE" ]; then
    fail "Téléchargement échoué ou archive vide."
    exit 1
fi
ok "Archive téléchargée ($(du -sh "$ARCHIVE" | cut -f1))"

step "Extraction..."
tar -xzf "$ARCHIVE" -C "$DEST" 2>/dev/null
EXPORT_DIR=$(find "$DEST" -maxdepth 1 -type d -name "miguation_*" | head -1)

if [ -z "$EXPORT_DIR" ]; then
    fail "Extraction échouée."
    exit 1
fi
ok "Extrait dans : $EXPORT_DIR"

rm -f "$ARCHIVE"

step "Lancement de l'importation..."
bash "$SCRIPT_DIR/import.sh" "$EXPORT_DIR"
