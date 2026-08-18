#!/bin/bash
set -uo pipefail

OS="$(uname -s)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

step() { echo -e "  ${CYAN}>> $1${RESET}"; }
ok()   { echo -e "  ${GREEN}OK $1${RESET}"; }
fail() { echo -e "  ${RED}!! $1${RESET}"; }

# ── Mots de passe forts ───────────────────────────────────────────────────────
MDP_WIFI=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)
TOKEN=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)
SSID="Miguation"
SERVER_PID=""
ARCHIVE=""
WIFI_IF=""

cleanup() {
    step "Nettoyage..."
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
    [ -n "$ARCHIVE" ] && rm -f "$ARCHIVE" || true
    if [ "$OS" != "Darwin" ] && [ -n "$WIFI_IF" ]; then
        nmcli device disconnect "$WIFI_IF" 2>/dev/null || true
    fi
    ok "Propre."
}
trap cleanup EXIT

# ── Exportation ───────────────────────────────────────────────────────────────
step "Exportation en cours..."
EXPORT_DIR=$(bash "$SCRIPT_DIR/export.sh" "$HOME/.miguation-wifi-tmp" 2>/dev/null | tail -1)

if [ -z "$EXPORT_DIR" ] || [ ! -d "$EXPORT_DIR" ]; then
    EXPORT_DIR=$(ls -td "$HOME/.miguation-wifi-tmp"/miguation_* 2>/dev/null | head -1)
fi
if [ -z "$EXPORT_DIR" ] || [ ! -d "$EXPORT_DIR" ]; then
    fail "Exportation échouée."
    exit 1
fi
ok "Export dans : $EXPORT_DIR"

# ── Créer archive unique ───────────────────────────────────────────────────────
step "Création de l'archive..."
ARCHIVE="$(dirname "$EXPORT_DIR")/miguation.tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname "$EXPORT_DIR")" "$(basename "$EXPORT_DIR")"
ok "Archive créée ($(du -sh "$ARCHIVE" | cut -f1))"

# ── Hotspot ───────────────────────────────────────────────────────────────────
step "Création du hotspot WiFi..."

if [ "$OS" = "Darwin" ]; then
    WIFI_IF=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2; exit}')
    echo ""
    echo -e "  ${YELLOW}Sur macOS, active le hotspot manuellement :${RESET}"
    echo "  Réglages Système → Général → Partage → Partage de connexion"
    echo "  Nom réseau : $SSID | Mot de passe : $MDP_WIFI"
    read -rp "  Appuie sur Entrée quand le hotspot est actif..."
    IP="192.168.3.1"
else
    WIFI_IF=$(nmcli device | awk '/wifi/{print $1; exit}')
    if [ -z "$WIFI_IF" ]; then
        fail "Aucun adaptateur WiFi trouvé."
        exit 1
    fi
    nmcli device wifi hotspot ifname "$WIFI_IF" ssid "$SSID" password "$MDP_WIFI" 2>/dev/null
    # Attendre que l'IP soit attribuée
    sleep 3
    IP=$(nmcli -g IP4.ADDRESS device show "$WIFI_IF" 2>/dev/null | cut -d'/' -f1)
    [ -z "$IP" ] && IP="10.42.0.1"
    ok "Hotspot démarré"
fi

# ── Serveur HTTP avec token dans l'URL ────────────────────────────────────────
step "Démarrage du serveur de transfert..."
PORT=8765
SERVE_DIR="$(dirname "$ARCHIVE")"

# Créer un sous-dossier avec le token pour sécuriser l'URL
TOKEN_DIR="$SERVE_DIR/$TOKEN"
mkdir -p "$TOKEN_DIR"
ln -sf "$ARCHIVE" "$TOKEN_DIR/miguation.tar.gz"

cd "$SERVE_DIR"
python3 -m http.server $PORT &>/dev/null &
SERVER_PID=$!
ok "Serveur démarré"

# ── Instructions ──────────────────────────────────────────────────────────────
echo ""
echo -e "  ${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "  ${GREEN}║   Sur le NOUVEAU PC :                                    ║${RESET}"
echo -e "  ${GREEN}║                                                          ║${RESET}"
echo -e "  ${GREEN}║   1. Connecte-toi au WiFi :                              ║${RESET}"
echo -e "  ${YELLOW}║      Nom      : $SSID                              ║${RESET}"
echo -e "  ${YELLOW}║      Mot de passe : $MDP_WIFI                ║${RESET}"
echo -e "  ${GREEN}║                                                          ║${RESET}"
echo -e "  ${GREEN}║   2. Lance miguation.sh → option 4                        ║${RESET}"
echo -e "  ${GREEN}║      URL de téléchargement :                             ║${RESET}"
echo -e "  ${YELLOW}║      http://$IP:$PORT/$TOKEN/miguation.tar.gz  ║${RESET}"
echo -e "  ${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Laisse cette fenêtre ouverte. Appuie sur Entrée quand c'est fini."
read -r
