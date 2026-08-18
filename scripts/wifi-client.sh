#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

echo ""
echo -e "  ${YELLOW}Connecte-toi d'abord au WiFi '$MIGUATION_SSID'.${RESET}"
echo -e "  ${YELLOW}(Le mot de passe est affiché sur l'ancien PC)${RESET}"
read -rp "  Appuie sur Entrée quand tu es connecté..."

read -rp "  Entre l'URL affichée sur l'ancien PC (http://...): " URL

if [ -z "$URL" ]; then
    fail "URL vide."
    exit 1
fi

DEST="$HOME/miguation-import"
ARCHIVE="$DEST/$MIGUATION_ARCHIVE"
mkdir -p "$DEST"

step "Téléchargement de l'archive..."

telecharger() {
    local url="$1" sortie="$2"
    if command -v curl &>/dev/null; then
        curl -fL --progress-bar --connect-timeout 15 --retry 3 -o "$sortie" "$url"
    elif command -v wget &>/dev/null; then
        wget --progress=bar --tries=3 --timeout=15 -O "$sortie" "$url"
    else
        fail "curl ou wget requis."
        exit 1
    fi
}

telecharger "$URL" "$ARCHIVE"

if [ ! -f "$ARCHIVE" ] || [ ! -s "$ARCHIVE" ]; then
    fail "Téléchargement échoué ou archive vide."
    exit 1
fi
ok "Archive téléchargée ($(du -sh "$ARCHIVE" | cut -f1))"

# ── Vérification d'intégrité ──────────────────────────────────────────────────
# Une archive tronquée s'extrait partiellement et produit une restauration
# incomplète sans le moindre message d'erreur. On compare l'empreinte publiée
# par le serveur avant d'aller plus loin.
step "Vérification de l'intégrité..."
SOMME_URL="$URL.sha256"
SOMME_FICHIER="$DEST/archive.sha256"

if telecharger "$SOMME_URL" "$SOMME_FICHIER" 2>/dev/null && [ -s "$SOMME_FICHIER" ]; then
    ATTENDU=$(cut -d' ' -f1 < "$SOMME_FICHIER")
    if command -v sha256sum &>/dev/null; then
        OBTENU=$(sha256sum "$ARCHIVE" | cut -d' ' -f1)
    elif command -v shasum &>/dev/null; then
        OBTENU=$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)
    else
        OBTENU=""
    fi

    if [ -z "$OBTENU" ]; then
        skip "sha256sum indisponible — intégrité non vérifiée"
    elif [ "$ATTENDU" = "$OBTENU" ]; then
        ok "Intégrité vérifiée"
    else
        fail "L'archive est corrompue (empreinte différente)."
        echo "    attendu : $ATTENDU"
        echo "    obtenu  : $OBTENU"
        rm -f "$ARCHIVE" "$SOMME_FICHIER"
        exit 1
    fi
    rm -f "$SOMME_FICHIER"
else
    skip "Empreinte indisponible — intégrité non vérifiée"
fi

step "Extraction..."
if ! tar -xzf "$ARCHIVE" -C "$DEST"; then
    fail "Extraction échouée — archive illisible."
    exit 1
fi

EXPORT_DIR=$(find "$DEST" -maxdepth 1 -type d -name "miguation_*" | head -1)
if [ -z "$EXPORT_DIR" ]; then
    fail "Extraction échouée — dossier de sauvegarde introuvable."
    exit 1
fi
ok "Extrait dans : $EXPORT_DIR"

rm -f "$ARCHIVE"

step "Lancement de l'importation..."
bash "$SCRIPT_DIR/import.sh" "$EXPORT_DIR"
