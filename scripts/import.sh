#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

OS="$(uname -s)"

verifier_dependances rsync || exit 1

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

# Tableau plutôt que chaîne + eval (cf. export.sh) : un chemin contenant une
# espace ou une apostrophe cassait la commande.
EXCLUSIONS=(
    --exclude=node_modules --exclude=.venv --exclude=__pycache__ --exclude=.cache
    --exclude=.git --exclude=dist --exclude=build --exclude=.next --exclude=vendor
)

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
        if rsync -a "${EXCLUSIONS[@]}" "$CHEMIN/" "$DST/" 2>/dev/null; then
            ok "$DST_NAME restauré"
        else
            fail "$DST_NAME — restauration incomplète"
        fi
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
    # Linux — dpkg : reinstaller sans désinstaller ce qui n'est pas dans la liste.
    # `dpkg --get-selections` écrit « paquet<TAB>install » : il faut filtrer sur la
    # colonne 2, pas chercher « :install » dans la colonne 1 (qui ne matche jamais).
    if [ -f "$SOURCE/logiciels/dpkg.txt" ] && command -v apt-get &>/dev/null; then
        NB_PAQUETS=$(dpkg_paquets_installes "$SOURCE/logiciels/dpkg.txt" | wc -l)
        if [ "$NB_PAQUETS" -gt 0 ]; then
            dpkg_paquets_installes "$SOURCE/logiciels/dpkg.txt" | \
                xargs -r sudo apt-get install -y --no-remove 2>/dev/null
            ok "dpkg — $NB_PAQUETS paquet(s) traité(s)"
        else
            skip "dpkg — aucun paquet dans la liste"
        fi
    fi
    if [ -f "$SOURCE/logiciels/snap.txt" ] && command -v snap &>/dev/null; then
        NB_SNAP=0
        while IFS=$'\t' read -r NAME TYPE; do
            [ -n "$NAME" ] || continue
            if [ "$TYPE" = "classic" ]; then
                sudo snap install "$NAME" --classic 2>/dev/null || true
            else
                sudo snap install "$NAME" 2>/dev/null || true
            fi
            NB_SNAP=$((NB_SNAP + 1))
        done < <(snap_paquets "$SOURCE/logiciels/snap.txt")
        ok "snap — $NB_SNAP paquet(s) traité(s)"
    fi
    if [ -f "$SOURCE/logiciels/flatpak.txt" ] && command -v flatpak &>/dev/null; then
        NB_FLATPAK=0
        while IFS= read -r APP; do
            [ -n "$APP" ] || continue
            flatpak install -y --noninteractive "$APP" 2>/dev/null || true
            NB_FLATPAK=$((NB_FLATPAK + 1))
        done < <(flatpak_paquets "$SOURCE/logiciels/flatpak.txt")
        ok "flatpak — $NB_FLATPAK paquet(s) traité(s)"
    fi
fi

# ── Variables d'environnement ─────────────────────────────────────────────────
step "Restauration des variables d'environnement..."

# Les fichiers de configuration existants sont sauvegardés avant d'être écrasés :
# sur une machine déjà configurée, les remplacer sans filet est destructif.
HORODATAGE="$(date +%Y%m%d-%H%M%S)"
for F in .bashrc .zshrc .bash_profile .profile; do
    if [ -f "$SOURCE/$F" ]; then
        if [ -f "$HOME/$F" ]; then
            cp "$HOME/$F" "$HOME/$F.miguation-backup-$HORODATAGE"
            skip "$F existant sauvegardé en $F.miguation-backup-$HORODATAGE"
        fi
        cp "$SOURCE/$F" "$HOME/$F" && ok "$F restauré"
    fi
done

# `export` dans ce script ne survit pas à sa propre sortie : l'ancienne version
# annonçait « restaurées » sans rien persister. On écrit un fichier dédié, chargé
# par les shells de connexion.
ENV_FICHIER="$HOME/.miguation_env"
if [ -f "$SOURCE/env_variables.txt" ]; then
    NB_VARS=0
    {
        echo "# Généré par Miguation le $(date)"
        echo "# Variables d'environnement importées depuis l'ancien ordinateur."
    } > "$ENV_FICHIER"

    while IFS= read -r LIGNE || [ -n "$LIGNE" ]; do
        case "$LIGNE" in ''|'#'*) continue ;; esac
        KEY="${LIGNE%%=*}"
        VALUE="${LIGNE#*=}"
        [ -n "$KEY" ] && [ "$KEY" != "$LIGNE" ] || continue
        if est_var_protegee "$KEY"; then
            continue
        fi
        printf 'export %s=%q\n' "$KEY" "$VALUE" >> "$ENV_FICHIER"
        NB_VARS=$((NB_VARS + 1))
    done < "$SOURCE/env_variables.txt"

    # Brancher le fichier sur les shells de l'utilisateur, une seule fois.
    LIGNE_SOURCE="[ -f \"\$HOME/.miguation_env\" ] && . \"\$HOME/.miguation_env\""
    for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$RC" ] || continue
        if ! grep -qF '.miguation_env' "$RC"; then
            printf '\n# Ajouté par Miguation\n%s\n' "$LIGNE_SOURCE" >> "$RC"
        fi
    done

    ok "$NB_VARS variable(s) restaurée(s) dans ~/.miguation_env (actives au prochain terminal)"
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
