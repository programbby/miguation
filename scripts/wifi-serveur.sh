#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

OS="$(uname -s)"

# ── Mots de passe forts ───────────────────────────────────────────────────────
MDP_WIFI=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)
TOKEN=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)
SSID="$MIGUATION_SSID"
SERVER_PID=""
ARCHIVE=""
WIFI_IF=""

TMP_DIR="$HOME/.miguation-wifi-tmp"

cleanup() {
    step "Nettoyage..."
    if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; fi
    if [ -n "$ARCHIVE" ]; then rm -f "$ARCHIVE"; fi
    # Le dossier temporaire contient une copie complète du dossier personnel
    # (marque-pages, fichiers, fichiers shell). Le laisser sur le disque après
    # le transfert serait une fuite de données au repos.
    case "$TMP_DIR" in
        "$HOME"/.miguation-wifi-tmp) rm -rf "$TMP_DIR" ;;
    esac
    if [ "$OS" != "Darwin" ] && [ -n "$WIFI_IF" ]; then
        nmcli device disconnect "$WIFI_IF" 2>/dev/null || true
    fi
    ok "Propre."
}
trap cleanup EXIT

# ── Exportation ───────────────────────────────────────────────────────────────
step "Exportation en cours..."
MIGUATION_NON_INTERACTIF=1 bash "$SCRIPT_DIR/export.sh" "$TMP_DIR" >/dev/null 2>&1

# export.sh dépose le chemin dans un marqueur : plus fiable que de lire sa
# dernière ligne de stdout, qui casse dès qu'un message est ajouté à la fin.
EXPORT_DIR=""
if [ -f "$TMP_DIR/.miguation-dernier-export" ]; then
    EXPORT_DIR="$(cat "$TMP_DIR/.miguation-dernier-export")"
fi
if [ -z "$EXPORT_DIR" ] || [ ! -d "$EXPORT_DIR" ]; then
    EXPORT_DIR=$(ls -td "$TMP_DIR"/miguation_* 2>/dev/null | head -1)
fi
if [ -z "$EXPORT_DIR" ] || [ ! -d "$EXPORT_DIR" ]; then
    fail "Exportation échouée."
    exit 1
fi
ok "Export dans : $EXPORT_DIR"

# ── Créer archive unique ───────────────────────────────────────────────────────
step "Création de l'archive..."
ARCHIVE="$(dirname "$EXPORT_DIR")/$MIGUATION_ARCHIVE"
tar -czf "$ARCHIVE" -C "$(dirname "$EXPORT_DIR")" "$(basename "$EXPORT_DIR")"
ok "Archive créée ($(du -sh "$ARCHIVE" | cut -f1))"

# Empreinte pour que le client détecte un téléchargement tronqué ou corrompu.
step "Calcul de l'empreinte..."
if command -v sha256sum &>/dev/null; then
    SOMME=$(sha256sum "$ARCHIVE" | cut -d' ' -f1)
elif command -v shasum &>/dev/null; then
    SOMME=$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)
else
    fail "sha256sum ou shasum requis."
    exit 1
fi
ok "SHA256 calculé"

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

# ── Serveur HTTP restreint à la route tokenisée ───────────────────────────────
step "Démarrage du serveur de transfert..."
PORT="$MIGUATION_PORT"

# Serveur dédié plutôt que `python3 -m http.server` : ce dernier publiait tout le
# répertoire (l'archive restait accessible sans le token, et le listing révélait
# le token). Ici seule la route /<token>/miguation.tar.gz répond.
python3 "$SCRIPT_DIR/lib/serveur.py" "$PORT" "$TOKEN" "$ARCHIVE" "$SOMME" &>/dev/null &
SERVER_PID=$!

sleep 1
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    fail "Le serveur n'a pas démarré (port $PORT déjà utilisé ?)."
    exit 1
fi
ok "Serveur démarré"

# ── Instructions ──────────────────────────────────────────────────────────────
# Pas d'encadré : la longueur du mot de passe et du token varie, donc une boîte
# à bordures fixes se désaligne systématiquement.
echo ""
echo -e "  ${GREEN}──────────── Sur le NOUVEAU PC ────────────${RESET}"
echo ""
echo -e "  ${GREEN}1. Connecte-toi à ce réseau WiFi :${RESET}"
echo -e "       Nom         : ${YELLOW}$SSID${RESET}"
echo -e "       Mot de passe: ${YELLOW}$MDP_WIFI${RESET}"
echo ""
echo -e "  ${GREEN}2. Lance miguation.sh puis choisis l'option 4.${RESET}"
echo -e "     Quand l'URL est demandée, saisis :"
echo -e "       ${YELLOW}http://$IP:$PORT/$TOKEN/$MIGUATION_ARCHIVE${RESET}"
echo ""
echo -e "  ${GREEN}───────────────────────────────────────────${RESET}"
echo ""
echo "  Laisse cette fenêtre ouverte. Appuie sur Entrée quand c'est fini."
read -r
