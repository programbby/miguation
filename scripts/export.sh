#!/bin/bash

OS="$(uname -s)"
DATE="$(date +%Y-%m-%d_%H-%M)"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'

step() { echo -e "  ${CYAN}>> $1${RESET}"; }
ok()   { echo -e "  ${GREEN}OK $1${RESET}"; }
skip() { echo -e "  ${YELLOW}-- $1${RESET}"; }

read -p "  Où sauvegarder ? (ex: /Volumes/USB/migration) : " DEST
EXPORT="$DEST/migratix_$DATE"
mkdir -p "$EXPORT"
RAPPORT=()

echo ""
echo "  Dossier : $EXPORT"

# ── 1. Fichiers utilisateur ─────────────────────────────────────────────────
step "Copie des fichiers personnels..."

DOSSIERS=(
    "$HOME/Documents:Documents"
    "$HOME/Desktop:Bureau"
    "$HOME/Pictures:Images"
    "$HOME/Movies:Videos"
    "$HOME/Music:Musique"
    "$HOME/Downloads:Telechargements"
    "$HOME/projets:projets"
    "$HOME/.claude:.claude"
)

for ITEM in "${DOSSIERS[@]}"; do
    SRC="${ITEM%%:*}"
    DST="${ITEM##*:}"
    if [ -d "$SRC" ]; then
        mkdir -p "$EXPORT/fichiers/$DST"
        rsync -a --delete "$SRC/" "$EXPORT/fichiers/$DST/" 2>/dev/null
        ok "$DST copié"
    else
        skip "$DST introuvable, ignoré"
    fi
done

# ── 2. Navigateurs ──────────────────────────────────────────────────────────
step "Migration des navigateurs..."

if [ "$OS" = "Darwin" ]; then
    CHROME_PATH="$HOME/Library/Application Support/Google/Chrome/Default"
    BRAVE_PATH="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default"
    FF_PATH="$HOME/Library/Application Support/Firefox/Profiles"
    SAFARI_BOOKMARKS="$HOME/Library/Safari/Bookmarks.plist"
else
    CHROME_PATH="$HOME/.config/google-chrome/Default"
    BRAVE_PATH="$HOME/.config/BraveSoftware/Brave-Browser/Default"
    FF_PATH="$HOME/.mozilla/firefox"
fi

for BROWSER in "Chrome:$CHROME_PATH" "Brave:$BRAVE_PATH"; do
    NOM="${BROWSER%%:*}"
    PATH_B="${BROWSER##*:}"
    if [ -d "$PATH_B" ]; then
        mkdir -p "$EXPORT/navigateurs/$NOM"
        [ -f "$PATH_B/Bookmarks" ] && cp "$PATH_B/Bookmarks" "$EXPORT/navigateurs/$NOM/" && ok "$NOM — marque-pages copiés"
        if [ -d "$PATH_B/Extensions" ]; then
            ls "$PATH_B/Extensions" > "$EXPORT/navigateurs/$NOM/extensions.txt"
            ok "$NOM — extensions listées"
        fi
    fi
done

if [ -d "$FF_PATH" ]; then
    mkdir -p "$EXPORT/navigateurs/Firefox"
    rsync -a "$FF_PATH/" "$EXPORT/navigateurs/Firefox/" 2>/dev/null
    ok "Firefox — profil complet copié"
fi

if [ "$OS" = "Darwin" ] && [ -f "$SAFARI_BOOKMARKS" ]; then
    mkdir -p "$EXPORT/navigateurs/Safari"
    cp "$SAFARI_BOOKMARKS" "$EXPORT/navigateurs/Safari/"
    ok "Safari — marque-pages copiés"
fi

RAPPORT+=("NAVIGATEURS : active la sync dans Paramètres > Synchronisation pour récupérer tes mots de passe.")

# ── 3. Logiciels ─────────────────────────────────────────────────────────────
step "Export des logiciels installés..."
mkdir -p "$EXPORT/logiciels"

if [ "$OS" = "Darwin" ]; then
    # macOS
    if command -v brew &>/dev/null; then
        brew list > "$EXPORT/logiciels/brew.txt"
        brew list --cask >> "$EXPORT/logiciels/brew.txt"
        ok "Homebrew — liste exportée"
    fi
    if command -v mas &>/dev/null; then
        mas list > "$EXPORT/logiciels/appstore.txt"
        ok "App Store — liste exportée"
    fi
    # Apps installées manuellement
    ls /Applications > "$EXPORT/logiciels/applications.txt"
    ok "Applications — liste exportée"
else
    # Linux
    if command -v dpkg &>/dev/null; then
        dpkg --get-selections > "$EXPORT/logiciels/dpkg.txt"
        ok "dpkg — liste exportée"
    fi
    if command -v rpm &>/dev/null; then
        rpm -qa > "$EXPORT/logiciels/rpm.txt"
        ok "rpm — liste exportée"
    fi
    if command -v snap &>/dev/null; then
        snap list > "$EXPORT/logiciels/snap.txt"
        ok "snap — liste exportée"
    fi
    if command -v flatpak &>/dev/null; then
        flatpak list > "$EXPORT/logiciels/flatpak.txt"
        ok "flatpak — liste exportée"
    fi
fi

# ── 4. Variables d'environnement ─────────────────────────────────────────────
step "Export des variables d'environnement..."
for F in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    [ -f "$F" ] && cp "$F" "$EXPORT/" && ok "$(basename $F) copié"
done

# ── 5. Rapport ───────────────────────────────────────────────────────────────
{
    echo "=== MIGRATIX — RAPPORT ==="
    echo "Date : $DATE | Système : $OS | Machine : $(hostname)"
    echo ""
    for LINE in "${RAPPORT[@]}"; do echo "$LINE"; done
    echo ""
    echo "PROCHAINE ÉTAPE :"
    echo "  Option 1 (USB) : copie ce dossier sur ta clé, lance migratix.sh sur le nouveau PC"
    echo "  Option 2 (WiFi): lance migratix.sh → option 3 sur cet ordi"
} > "$EXPORT/RAPPORT.txt"

echo ""
echo -e "  ${GREEN}════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}EXPORTATION TERMINÉE${RESET}"
echo -e "  ${GREEN}$EXPORT${RESET}"
echo -e "  ${GREEN}════════════════════════════════════════${RESET}"
echo ""

echo "$EXPORT"
