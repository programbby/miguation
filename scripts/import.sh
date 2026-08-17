#!/bin/bash

OS="$(uname -s)"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

step() { echo -e "  ${CYAN}>> $1${RESET}"; }
ok()   { echo -e "  ${GREEN}OK $1${RESET}"; }
skip() { echo -e "  ${YELLOW}-- $1${RESET}"; }

SOURCE="$1"

if [ -z "$SOURCE" ]; then
    read -p "  Où se trouve la sauvegarde ? : " SOURCE
fi

if [ ! -d "$SOURCE" ]; then
    echo -e "  ${RED}ERREUR : dossier introuvable.${RESET}"
    exit 1
fi

echo ""
echo "  Source : $SOURCE"

# ── 1. Fichiers utilisateur ─────────────────────────────────────────────────
step "Restauration des fichiers..."

DOSSIERS=(
    "Documents:$HOME/Documents"
    "Bureau:$HOME/Desktop"
    "Images:$HOME/Pictures"
    "Videos:$HOME/Movies"
    "Musique:$HOME/Music"
    "Telechargements:$HOME/Downloads"
    "projets:$HOME/projets"
    ".claude:$HOME/.claude"
)

for ITEM in "${DOSSIERS[@]}"; do
    SRC="${ITEM%%:*}"
    DST="${ITEM##*:}"
    CHEMIN="$SOURCE/fichiers/$SRC"
    if [ -d "$CHEMIN" ]; then
        mkdir -p "$DST"
        rsync -a "$CHEMIN/" "$DST/" 2>/dev/null
        ok "$SRC restauré"
    else
        skip "$SRC absent, ignoré"
    fi
done

# ── 2. Navigateurs ──────────────────────────────────────────────────────────
step "Restauration des navigateurs..."

if [ "$OS" = "Darwin" ]; then
    CHROME_PATH="$HOME/Library/Application Support/Google/Chrome/Default"
    BRAVE_PATH="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default"
    FF_PATH="$HOME/Library/Application Support/Firefox/Profiles"
else
    CHROME_PATH="$HOME/.config/google-chrome/Default"
    BRAVE_PATH="$HOME/.config/BraveSoftware/Brave-Browser/Default"
    FF_PATH="$HOME/.mozilla/firefox"
fi

for BROWSER in "Chrome:$CHROME_PATH" "Brave:$BRAVE_PATH"; do
    NOM="${BROWSER%%:*}"
    PATH_B="${BROWSER##*:}"
    BK="$SOURCE/navigateurs/$NOM/Bookmarks"
    if [ -f "$BK" ] && [ -d "$PATH_B" ]; then
        cp "$BK" "$PATH_B/Bookmarks"
        ok "$NOM — marque-pages restaurés (redémarre le navigateur)"
    elif [ -f "$BK" ]; then
        skip "$NOM — pas installé sur ce PC, installe-le d'abord"
    fi
    EXT="$SOURCE/navigateurs/$NOM/extensions.txt"
    if [ -f "$EXT" ]; then
        echo -e "\n  ${YELLOW}Extensions $NOM à réinstaller :${RESET}"
        cat "$EXT" | while read -r line; do echo "    - $line"; done
    fi
done

FF_SRC="$SOURCE/navigateurs/Firefox"
if [ -d "$FF_SRC" ]; then
    mkdir -p "$FF_PATH"
    rsync -a "$FF_SRC/" "$FF_PATH/" 2>/dev/null
    ok "Firefox — profil restauré"
fi

SAFARI_BK="$SOURCE/navigateurs/Safari/Bookmarks.plist"
if [ "$OS" = "Darwin" ] && [ -f "$SAFARI_BK" ]; then
    cp "$SAFARI_BK" "$HOME/Library/Safari/Bookmarks.plist"
    ok "Safari — marque-pages restaurés"
fi

# ── 3. Logiciels ─────────────────────────────────────────────────────────────
step "Réinstallation des logiciels..."

if [ "$OS" = "Darwin" ]; then
    if [ -f "$SOURCE/logiciels/brew.txt" ] && command -v brew &>/dev/null; then
        xargs brew install < "$SOURCE/logiciels/brew.txt" 2>/dev/null
        ok "Homebrew — logiciels réinstallés"
    fi
    if [ -f "$SOURCE/logiciels/appstore.txt" ] && command -v mas &>/dev/null; then
        awk '{print $1}' "$SOURCE/logiciels/appstore.txt" | xargs mas install 2>/dev/null
        ok "App Store — apps réinstallées"
    fi
else
    if [ -f "$SOURCE/logiciels/dpkg.txt" ] && command -v dpkg &>/dev/null; then
        sudo dpkg --set-selections < "$SOURCE/logiciels/dpkg.txt"
        sudo apt-get dselect-upgrade -y 2>/dev/null
        ok "dpkg — paquets restaurés"
    fi
    if [ -f "$SOURCE/logiciels/snap.txt" ] && command -v snap &>/dev/null; then
        tail -n +2 "$SOURCE/logiciels/snap.txt" | awk '{print $1}' | xargs -I{} sudo snap install {} 2>/dev/null
        ok "snap — paquets restaurés"
    fi
    if [ -f "$SOURCE/logiciels/flatpak.txt" ] && command -v flatpak &>/dev/null; then
        tail -n +2 "$SOURCE/logiciels/flatpak.txt" | awk '{print $2}' | xargs -I{} flatpak install -y {} 2>/dev/null
        ok "flatpak — paquets restaurés"
    fi
fi

# ── 4. Variables d'environnement ─────────────────────────────────────────────
step "Restauration des variables d'environnement..."
for F in .bashrc .zshrc .bash_profile .profile; do
    if [ -f "$SOURCE/$F" ]; then
        cp "$SOURCE/$F" "$HOME/$F"
        ok "$F restauré"
    fi
done

# ── 5. Rapport ───────────────────────────────────────────────────────────────
RAPPORT="$SOURCE/RAPPORT.txt"
if [ -f "$RAPPORT" ]; then
    echo ""
    echo -e "  ${YELLOW}════════ ACTIONS MANUELLES ════════${RESET}"
    grep -E "LICENCE|NAVIGATEUR" "$RAPPORT" | while read -r line; do
        echo -e "  ${YELLOW}$line${RESET}"
    done
    echo -e "  ${YELLOW}═══════════════════════════════════${RESET}"
fi

echo ""
echo -e "  ${GREEN}════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}IMPORTATION TERMINÉE${RESET}"
echo -e "  ${GREEN}Redémarre ton PC pour que tout soit actif${RESET}"
echo -e "  ${GREEN}════════════════════════════════════════${RESET}"
echo ""
