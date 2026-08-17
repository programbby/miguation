#!/bin/bash

OS="${1:-$(uname -s)}"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MDP="migratix$(shuf -i 1000-9999 -n 1 2>/dev/null || echo $RANDOM)"
SSID="Migratix"

step() { echo -e "  ${CYAN}>> $1${RESET}"; }
ok()   { echo -e "  ${GREEN}OK $1${RESET}"; }
fail() { echo -e "  ${RED}!! $1${RESET}"; }

# ── Créer le hotspot ─────────────────────────────────────────────────────────
step "Création du hotspot WiFi..."

if [ "$OS" = "Darwin" ]; then
    # macOS — Internet Sharing via networksetup
    # Trouver l'interface WiFi
    WIFI_IF=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
    if [ -z "$WIFI_IF" ]; then
        fail "Interface WiFi non trouvée."
        exit 1
    fi
    # macOS ne permet pas de créer un hotspot par ligne de commande facilement
    # On passe en mode réseau WiFi normal avec instruction manuelle
    IP=$(ipconfig getifaddr "$WIFI_IF" 2>/dev/null)
    echo ""
    echo -e "  ${YELLOW}Sur macOS, active le hotspot manuellement :${RESET}"
    echo "  Préférences Système → Partage → Partage de connexion"
    echo "  Partager depuis : Ethernet (ou ta connexion actuelle)"
    echo "  Pour les ordinateurs utilisant : Wi-Fi"
    echo "  Options Wi-Fi : SSID=$SSID, Mot de passe=$MDP"
    echo ""
    read -p "  Appuie sur Entrée quand le hotspot est actif..."
    IP="192.168.3.1"
else
    # Linux — nmcli
    if ! command -v nmcli &>/dev/null; then
        fail "nmcli non trouvé. Installe NetworkManager."
        exit 1
    fi
    WIFI_IF=$(nmcli device | awk '/wifi/{print $1; exit}')
    nmcli device wifi hotspot ifname "$WIFI_IF" ssid "$SSID" password "$MDP" 2>/dev/null
    if [ $? -ne 0 ]; then
        fail "Impossible de créer le hotspot."
        exit 1
    fi
    IP=$(nmcli -g IP4.ADDRESS device show "$WIFI_IF" | cut -d'/' -f1)
    ok "Hotspot créé"
fi

# ── Exporter ─────────────────────────────────────────────────────────────────
step "Exportation en cours..."
EXPORT_DIR=$(bash "$SCRIPT_DIR/export.sh" | tail -1)

# ── Partager le dossier ───────────────────────────────────────────────────────
step "Partage du dossier en réseau..."
PORT=8765
cd "$EXPORT_DIR"
python3 -m http.server $PORT &>/dev/null &
SERVER_PID=$!
ok "Serveur démarré"

# ── Instructions ─────────────────────────────────────────────────────────────
echo ""
echo -e "  ${GREEN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "  ${GREEN}║  Sur le NOUVEAU PC :                         ║${RESET}"
echo -e "  ${GREEN}║                                              ║${RESET}"
echo -e "  ${GREEN}║  1. Connecte-toi au WiFi :                   ║${RESET}"
echo -e "  ${YELLOW}║     Nom      : $SSID                     ║${RESET}"
echo -e "  ${YELLOW}║     Mot de passe : $MDP              ║${RESET}"
echo -e "  ${GREEN}║                                              ║${RESET}"
echo -e "  ${GREEN}║  2. Lance migratix.sh → option 4             ║${RESET}"
echo -e "  ${GREEN}╚══════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Laisse cette fenêtre ouverte. Appuie sur Entrée quand c'est fini."
read

# ── Nettoyage ─────────────────────────────────────────────────────────────────
kill $SERVER_PID 2>/dev/null
if [ "$OS" != "Darwin" ]; then
    nmcli device disconnect "$WIFI_IF" 2>/dev/null
fi
ok "Transfert terminé, hotspot fermé."
