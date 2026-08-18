#!/bin/bash
set -euo pipefail

OS="$(uname -s)"
DATE="$(date +%Y-%m-%d_%H-%M)"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

step() { echo -e "  ${CYAN}>> $1${RESET}"; }
ok()   { echo -e "  ${GREEN}OK $1${RESET}"; }
skip() { echo -e "  ${YELLOW}-- $1${RESET}"; }
fail() { echo -e "  ${RED}!! $1${RESET}"; }

# ── Admin ────────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ] && [ "$OS" != "Darwin" ]; then
    echo -e "  ${YELLOW}Conseil : lance avec sudo pour une copie complète.${RESET}"
fi

# ── Destination ───────────────────────────────────────────────────────────────
if [ -n "${1:-}" ]; then
    DEST="$1"
else
    read -rp "  Où sauvegarder ? (ex: /Volumes/USB/migration) : " DEST
fi

EXPORT="$DEST/miguation_$DATE"
mkdir -p "$EXPORT"
LOG="$EXPORT/miguation.log"
echo "=== EXPORT DÉMARRÉ ===" > "$LOG"

# ── Navigateurs ouverts ───────────────────────────────────────────────────────
BROWSERS_OUVERTS=()
for B in "Google Chrome" "Firefox" "Brave Browser" "Microsoft Edge"; do
    if pgrep -f "$B" &>/dev/null; then BROWSERS_OUVERTS+=("$B"); fi
done
if [ ${#BROWSERS_OUVERTS[@]} -gt 0 ]; then
    echo -e "  ${YELLOW}ATTENTION : ferme ces navigateurs pour une copie complète :${RESET}"
    for B in "${BROWSERS_OUVERTS[@]}"; do echo "    - $B"; done
    read -rp "  Continuer quand même ? (o/n) : " REP
    [ "$REP" != "o" ] && exit 0
fi

# ── Espace disque ─────────────────────────────────────────────────────────────
step "Vérification espace disque..."
TAILLE=0
for D in "$HOME/Documents" "$HOME/Desktop" "$HOME/Pictures" "$HOME/Movies" \
         "$HOME/Music" "$HOME/Downloads" "$HOME/projets" "$HOME/.claude"; do
    [ -d "$D" ] && TAILLE=$((TAILLE + $(du -sk "$D" 2>/dev/null | cut -f1)))
done
if [ "$OS" = "Darwin" ]; then
    LIBRE=$(df -k "$DEST" 2>/dev/null | awk 'NR==2{print $4}')
else
    LIBRE=$(df -k "$DEST" 2>/dev/null | awk 'NR==2{print $4}')
fi
if [ -n "$LIBRE" ] && [ "$TAILLE" -gt "$LIBRE" ]; then
    fail "Espace insuffisant sur la destination."
    exit 1
fi
ok "Espace OK"

# ── Fichiers utilisateur ──────────────────────────────────────────────────────
step "Copie des fichiers personnels..."

EXCLUSIONS="--exclude=node_modules --exclude=.venv --exclude=__pycache__ --exclude=.cache \
    --exclude=.git --exclude=dist --exclude=build --exclude=.next --exclude=vendor \
    --exclude='*.tmp' --exclude=Thumbs.db"

declare -A DOSSIERS=(
    ["Documents"]="$HOME/Documents"
    ["Bureau"]="$HOME/Desktop"
    ["Images"]="$HOME/Pictures"
    ["Videos"]="$HOME/Movies"
    ["Musique"]="$HOME/Music"
    ["Telechargements"]="$HOME/Downloads"
    ["projets"]="$HOME/projets"
    [".claude"]="$HOME/.claude"
)

for DST_NAME in "${!DOSSIERS[@]}"; do
    SRC="${DOSSIERS[$DST_NAME]}"
    if [ -d "$SRC" ]; then
        mkdir -p "$EXPORT/fichiers/$DST_NAME"
        eval rsync -a $EXCLUSIONS "\"$SRC/\"" "\"$EXPORT/fichiers/$DST_NAME/\"" 2>>"$LOG" && ok "$DST_NAME copié" || fail "$DST_NAME — copie incomplète"
    else
        skip "$DST_NAME introuvable"
    fi
done

# ── Navigateurs ───────────────────────────────────────────────────────────────
step "Migration des navigateurs..."

if [ "$OS" = "Darwin" ]; then
    declare -A CHROME_PATHS=(
        ["Chrome"]="$HOME/Library/Application Support/Google/Chrome/Default"
        ["Edge"]="$HOME/Library/Application Support/Microsoft Edge/Default"
        ["Brave"]="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default"
    )
    FF_SRC="$HOME/Library/Application Support/Firefox"
else
    declare -A CHROME_PATHS=(
        ["Chrome"]="$HOME/.config/google-chrome/Default"
        ["Edge"]="$HOME/.config/microsoft-edge/Default"
        ["Brave"]="$HOME/.config/BraveSoftware/Brave-Browser/Default"
    )
    FF_SRC="$HOME/.mozilla/firefox"
fi

for BROWSER in "${!CHROME_PATHS[@]}"; do
    PATH_B="${CHROME_PATHS[$BROWSER]}"
    if [ -d "$PATH_B" ]; then
        mkdir -p "$EXPORT/navigateurs/$BROWSER"
        [ -f "$PATH_B/Bookmarks" ] && cp "$PATH_B/Bookmarks" "$EXPORT/navigateurs/$BROWSER/" && ok "$BROWSER — marque-pages copiés"
        if [ -d "$PATH_B/Extensions" ]; then
            ls "$PATH_B/Extensions" > "$EXPORT/navigateurs/$BROWSER/extensions.txt"
            ok "$BROWSER — extensions listées"
        fi
    fi
done

# Firefox (profil complet + profiles.ini)
if [ -d "$FF_SRC/Profiles" ]; then
    mkdir -p "$EXPORT/navigateurs/Firefox"
    rsync -a "$FF_SRC/Profiles/" "$EXPORT/navigateurs/Firefox/Profiles/" 2>>"$LOG"
    [ -f "$FF_SRC/profiles.ini" ] && cp "$FF_SRC/profiles.ini" "$EXPORT/navigateurs/Firefox/"
    ok "Firefox — profil complet copié (avec profiles.ini)"
fi

# Safari (macOS)
if [ "$OS" = "Darwin" ] && [ -f "$HOME/Library/Safari/Bookmarks.plist" ]; then
    mkdir -p "$EXPORT/navigateurs/Safari"
    cp "$HOME/Library/Safari/Bookmarks.plist" "$EXPORT/navigateurs/Safari/"
    ok "Safari — marque-pages copiés"
fi

# ── Logiciels ─────────────────────────────────────────────────────────────────
step "Export des logiciels installés..."
mkdir -p "$EXPORT/logiciels"

if [ "$OS" = "Darwin" ]; then
    if command -v brew &>/dev/null; then
        brew list --formula > "$EXPORT/logiciels/brew-formulas.txt" 2>>"$LOG"
        brew list --cask    > "$EXPORT/logiciels/brew-casks.txt"    2>>"$LOG"
        ok "Homebrew — formulas et casks exportés séparément"
    fi
    if command -v mas &>/dev/null; then
        mas list > "$EXPORT/logiciels/appstore.txt" 2>>"$LOG"
        ok "App Store — liste exportée"
    fi
    ls /Applications > "$EXPORT/logiciels/applications.txt" 2>>"$LOG"
    ok "Applications — liste exportée"
else
    command -v dpkg    &>/dev/null && dpkg --get-selections > "$EXPORT/logiciels/dpkg.txt"    2>>"$LOG" && ok "dpkg exporté"
    command -v rpm     &>/dev/null && rpm -qa               > "$EXPORT/logiciels/rpm.txt"     2>>"$LOG" && ok "rpm exporté"
    command -v snap    &>/dev/null && snap list             > "$EXPORT/logiciels/snap.txt"    2>>"$LOG" && ok "snap exporté"
    command -v flatpak &>/dev/null && flatpak list --columns=application,branch > "$EXPORT/logiciels/flatpak.txt" 2>>"$LOG" && ok "flatpak exporté"
fi

# ── Variables d'environnement (filtre secrets) ────────────────────────────────
step "Export des variables d'environnement..."
SECRET_PATTERN='KEY|SECRET|TOKEN|PASSWORD|PASS|PASSWD|CREDENTIAL|API|AUTH|PRIVATE|OAUTH'

for F in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    [ -f "$F" ] && cp "$F" "$EXPORT/" && ok "$(basename "$F") copié"
done

# Variables d'env en excluant les secrets
SECRETS_TROUVÉS=()
printenv | while IFS='=' read -r KEY VALUE; do
    if echo "$KEY" | grep -qiE "$SECRET_PATTERN"; then
        SECRETS_TROUVÉS+=("$KEY")
    else
        echo "$KEY=$VALUE"
    fi
done > "$EXPORT/env_variables.txt"

if [ ${#SECRETS_TROUVÉS[@]} -gt 0 ]; then
    echo ""
    echo -e "  ${YELLOW}SECRETS non copiés (pour ta sécurité) :${RESET}"
    for S in "${SECRETS_TROUVÉS[@]}"; do echo "    - $S"; done
fi

# ── Rapport ───────────────────────────────────────────────────────────────────
{
    echo "=== MIGUATION — RAPPORT ==="
    echo "Date : $DATE | Système : $OS | Machine : $(hostname)"
    echo ""
    echo "NAVIGATEURS : active la synchronisation dans Paramètres > Sync pour récupérer tes mots de passe."
    echo ""
    echo "PROCHAINE ÉTAPE :"
    echo "  Clé USB : copie ce dossier, lance miguation.sh sur le nouveau PC"
    echo "  WiFi    : lance miguation.sh → option 3 sur cet ordi"
} > "$EXPORT/RAPPORT.txt"

echo ""
echo -e "  ${GREEN}════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}EXPORTATION TERMINÉE${RESET}"
echo -e "  ${GREEN}$EXPORT${RESET}"
echo -e "  ${GREEN}════════════════════════════════════════${RESET}"
echo ""

# Retourner le chemin pour les scripts wifi
echo "$EXPORT"
