#!/bin/bash
set -uo pipefail

OS="$(uname -s)"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

step() { echo -e "  ${CYAN}>> $1${RESET}"; }
ok()   { echo -e "  ${GREEN}OK $1${RESET}"; }
skip() { echo -e "  ${YELLOW}-- $1${RESET}"; }
fail() { echo -e "  ${RED}!! $1${RESET}"; }

SOURCE="${1:-}"
if [ -z "$SOURCE" ]; then
    read -rp "  Où se trouve la sauvegarde ? : " SOURCE
fi

if [ ! -d "$SOURCE" ]; then
    fail "Dossier introuvable : $SOURCE"
    exit 1
fi

# ── Navigateurs ouverts ───────────────────────────────────────────────────────
for B in "Google Chrome" "Firefox" "Brave Browser" "Microsoft Edge"; do
    if pgrep -f "$B" &>/dev/null; then
        echo -e "  ${YELLOW}ATTENTION : ferme $B avant de continuer.${RESET}"
    fi
done

echo ""
echo "  Source : $SOURCE"

EXCLUSIONS="--exclude=node_modules --exclude=.venv --exclude=__pycache__ --exclude=.cache \
    --exclude=.git --exclude=dist --exclude=build --exclude=.next --exclude=vendor"

# ── Fichiers utilisateur ──────────────────────────────────────────────────────
step "Restauration des fichiers..."

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
    CHEMIN="$SOURCE/fichiers/$DST_NAME"
    DST="${DOSSIERS[$DST_NAME]}"
    if [ -d "$CHEMIN" ]; then
        mkdir -p "$DST"
        eval rsync -a $EXCLUSIONS "\"$CHEMIN/\"" "\"$DST/\"" 2>/dev/null && ok "$DST_NAME restauré" || fail "$DST_NAME — restauration incomplète"
    else
        skip "$DST_NAME absent"
    fi
done

# ── Navigateurs ───────────────────────────────────────────────────────────────
step "Restauration des navigateurs..."

if [ "$OS" = "Darwin" ]; then
    declare -A CHROME_PATHS=(
        ["Chrome"]="$HOME/Library/Application Support/Google/Chrome/Default"
        ["Edge"]="$HOME/Library/Application Support/Microsoft Edge/Default"
        ["Brave"]="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default"
    )
    FF_DST="$HOME/Library/Application Support/Firefox"
else
    declare -A CHROME_PATHS=(
        ["Chrome"]="$HOME/.config/google-chrome/Default"
        ["Edge"]="$HOME/.config/microsoft-edge/Default"
        ["Brave"]="$HOME/.config/BraveSoftware/Brave-Browser/Default"
    )
    FF_DST="$HOME/.mozilla/firefox"
fi

for BROWSER in "${!CHROME_PATHS[@]}"; do
    BK="$SOURCE/navigateurs/$BROWSER/Bookmarks"
    PATH_B="${CHROME_PATHS[$BROWSER]}"
    if [ -f "$BK" ]; then
        if [ -d "$PATH_B" ]; then
            cp "$BK" "$PATH_B/Bookmarks" && ok "$BROWSER — marque-pages restaurés (redémarre le navigateur)"
        else
            skip "$BROWSER — non installé sur ce PC"
        fi
    fi
    EXT="$SOURCE/navigateurs/$BROWSER/extensions.txt"
    if [ -f "$EXT" ]; then
        echo -e "\n  ${YELLOW}Extensions $BROWSER à réinstaller :${RESET}"
        while IFS= read -r line; do echo "    - $line"; done < "$EXT"
    fi
done

# Firefox
FF_SRC="$SOURCE/navigateurs/Firefox/Profiles"
FF_INI="$SOURCE/navigateurs/Firefox/profiles.ini"
if [ -d "$FF_SRC" ]; then
    mkdir -p "$FF_DST/Profiles"
    rsync -a "$FF_SRC/" "$FF_DST/Profiles/" 2>/dev/null
    [ -f "$FF_INI" ] && cp "$FF_INI" "$FF_DST/profiles.ini"
    ok "Firefox — profil restauré"
fi

# Safari
SAFARI_BK="$SOURCE/navigateurs/Safari/Bookmarks.plist"
if [ "$OS" = "Darwin" ] && [ -f "$SAFARI_BK" ]; then
    cp "$SAFARI_BK" "$HOME/Library/Safari/Bookmarks.plist"
    ok "Safari — marque-pages restaurés"
fi

# ── Logiciels ─────────────────────────────────────────────────────────────────
step "Réinstallation des logiciels..."

if [ "$OS" = "Darwin" ]; then
    if command -v brew &>/dev/null; then
        # Formulas et casks séparés
        if [ -f "$SOURCE/logiciels/brew-formulas.txt" ]; then
            xargs brew install --formula < "$SOURCE/logiciels/brew-formulas.txt" 2>/dev/null && ok "Homebrew formulas réinstallées"
        fi
        if [ -f "$SOURCE/logiciels/brew-casks.txt" ]; then
            xargs brew install --cask < "$SOURCE/logiciels/brew-casks.txt" 2>/dev/null && ok "Homebrew casks réinstallés"
        fi
    fi
    if command -v mas &>/dev/null && [ -f "$SOURCE/logiciels/appstore.txt" ]; then
        awk '{print $1}' "$SOURCE/logiciels/appstore.txt" | xargs -I{} mas install {} 2>/dev/null
        ok "App Store — apps réinstallées"
    fi
else
    # Linux — dpkg : reinstaller sans désinstaller ce qui n'est pas dans la liste
    if [ -f "$SOURCE/logiciels/dpkg.txt" ] && command -v apt-get &>/dev/null; then
        awk '{print $1}' "$SOURCE/logiciels/dpkg.txt" | grep ':install$' | sed 's/:install//' | \
            xargs sudo apt-get install -y --no-remove 2>/dev/null && ok "dpkg — paquets restaurés"
    fi
    if [ -f "$SOURCE/logiciels/snap.txt" ] && command -v snap &>/dev/null; then
        # Gérer les snaps classic séparément
        tail -n +2 "$SOURCE/logiciels/snap.txt" | while read -r NAME VERSION REV TRACKING PUBLISHER NOTES; do
            if echo "$NOTES" | grep -q "classic"; then
                sudo snap install "$NAME" --classic 2>/dev/null || true
            else
                sudo snap install "$NAME" 2>/dev/null || true
            fi
        done
        ok "snap — paquets restaurés"
    fi
    if [ -f "$SOURCE/logiciels/flatpak.txt" ] && command -v flatpak &>/dev/null; then
        while IFS=$'\t' read -r APP BRANCH; do
            flatpak install -y --noninteractive "$APP" 2>/dev/null || true
        done < <(tail -n +1 "$SOURCE/logiciels/flatpak.txt")
        ok "flatpak — paquets restaurés"
    fi
fi

# ── Variables d'environnement ─────────────────────────────────────────────────
step "Restauration des variables d'environnement..."

VARS_PROTEGEES="HOME|USER|SHELL|PATH|TERM|DISPLAY|LANG|LC_|PWD|OLDPWD|SHLVL|LOGNAME"

for F in .bashrc .zshrc .bash_profile .profile; do
    if [ -f "$SOURCE/$F" ]; then
        cp "$SOURCE/$F" "$HOME/$F" && ok "$F restauré"
    fi
done

if [ -f "$SOURCE/env_variables.txt" ]; then
    while IFS='=' read -r KEY VALUE; do
        if ! echo "$KEY" | grep -qE "$VARS_PROTEGEES"; then
            export "$KEY=$VALUE" 2>/dev/null || true
        fi
    done < "$SOURCE/env_variables.txt"
    ok "Variables d'environnement restaurées"
fi

# ── Rapport ───────────────────────────────────────────────────────────────────
RAPPORT="$SOURCE/RAPPORT.txt"
if [ -f "$RAPPORT" ]; then
    echo ""
    echo -e "  ${YELLOW}════════ ACTIONS MANUELLES ════════${RESET}"
    grep -E "SECRETS|NAVIGATEUR|LICENCE" "$RAPPORT" | while IFS= read -r line; do
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
