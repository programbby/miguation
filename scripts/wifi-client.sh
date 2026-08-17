#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

echo ""
echo -e "  ${YELLOW}Connecte-toi au WiFi 'Migratix' avant de continuer.${RESET}"
read -p "  Appuie sur Entrée quand c'est fait..."

# L'ancien PC sert les fichiers sur le port 8765
# Sur Linux hotspot : IP source = première adresse du sous-réseau
# On essaie les IPs communes des hotspots
POSSIBLE_IPS=("192.168.137.1" "192.168.3.1" "10.42.0.1")
SERVER_IP=""

for IP in "${POSSIBLE_IPS[@]}"; do
    if curl -s --connect-timeout 2 "http://$IP:8765/" &>/dev/null; then
        SERVER_IP="$IP"
        break
    fi
done

if [ -z "$SERVER_IP" ]; then
    read -p "  IP non trouvée automatiquement. Entre l'IP de l'ancien PC : " SERVER_IP
fi

echo -e "  ${CYAN}>> Connexion à $SERVER_IP...${RESET}"

DEST="$HOME/migratix-import"
mkdir -p "$DEST"

# Télécharger tous les fichiers via wget ou curl
if command -v wget &>/dev/null; then
    wget -r -np -nH -q --show-progress "http://$SERVER_IP:8765/" -P "$DEST"
elif command -v curl &>/dev/null; then
    curl -s "http://$SERVER_IP:8765/" | grep -oP '(?<=href=")[^"]+' | while read -r FILE; do
        mkdir -p "$DEST/$(dirname $FILE)"
        curl -s "http://$SERVER_IP:8765/$FILE" -o "$DEST/$FILE"
    done
else
    echo -e "  ${RED}wget ou curl requis.${RESET}"
    exit 1
fi

echo -e "  ${GREEN}OK Fichiers reçus. Lancement de l'importation...${RESET}"
bash "$SCRIPT_DIR/import.sh" "$DEST"
