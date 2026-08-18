#!/bin/bash
# Fonctions et constantes partagées entre les scripts Miguation.
# Ce fichier ne fait aucun effet de bord : il peut être sourcé par les tests.

# ── Identité réseau ───────────────────────────────────────────────────────────
# Une seule source de vérité : le serveur crée ce SSID, le client l'annonce.
# Les scripts qui sourcent ce fichier les consomment — shellcheck ne peut pas
# le voir depuis ici.
# shellcheck disable=SC2034
MIGUATION_SSID="Miguation"
# shellcheck disable=SC2034
MIGUATION_PORT=8765
# shellcheck disable=SC2034
MIGUATION_ARCHIVE="miguation.tar.gz"

# ── Affichage ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

step() { echo -e "  ${CYAN}>> $1${RESET}"; }
ok()   { echo -e "  ${GREEN}OK $1${RESET}"; }
skip() { echo -e "  ${YELLOW}-- $1${RESET}"; }
fail() { echo -e "  ${RED}!! $1${RESET}"; }

# ── Dépendances ───────────────────────────────────────────────────────────────
# Sans rsync, la copie échoue dossier par dossier mais le script continue et
# annonce « TERMINÉE » : l'utilisateur repart avec une sauvegarde vide en croyant
# ses fichiers à l'abri. On préfère refuser de démarrer.
#
# verifier_dependances CMD...
verifier_dependances() {
    local manquantes=() cmd
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || manquantes+=("$cmd")
    done
    if [ ${#manquantes[@]} -gt 0 ]; then
        fail "Commande(s) requise(s) introuvable(s) : ${manquantes[*]}"
        echo "     Installe-les puis relance :"
        echo "       Debian/Ubuntu : sudo apt install ${manquantes[*]}"
        echo "       Fedora        : sudo dnf install ${manquantes[*]}"
        echo "       macOS         : brew install ${manquantes[*]}"
        return 1
    fi
    return 0
}

# ── Détection des secrets ─────────────────────────────────────────────────────
# Deux familles de motifs :
#  - sous-chaînes sans ambiguïté (SECRET, TOKEN…) qui ne produisent pas de faux positifs
#  - mots entiers délimités par _ ou par les bornes du nom (KEY, API, PASS…), pour
#    éviter que COMPASS_HOME, RAPID_TIMEOUT ou MONKEY_MODE soient pris pour des secrets
MIGUATION_SECRET_PATTERN='SECRET|TOKEN|PASSWORD|PASSWD|PASSPHRASE|CREDENTIAL|PRIVATE|OAUTH|APIKEY|(^|_)(KEY|API|AUTH|PASS|PAT|SALT|SIG|SIGNATURE|CERT|SESSION|COOKIE)(_|$)'

# URL contenant des identifiants en clair : scheme://user:motdepasse@hote
MIGUATION_SECRET_VALUE_PATTERN='://[^/[:space:]]+:[^/[:space:]]+@'

# est_secret NOM [VALEUR]
# Vrai (0) si la variable doit être exclue de la sauvegarde.
est_secret() {
    local nom="$1" valeur="${2-}"
    if printf '%s' "$nom" | grep -qiE "$MIGUATION_SECRET_PATTERN"; then
        return 0
    fi
    if [ -n "$valeur" ] && printf '%s' "$valeur" | grep -qE "$MIGUATION_SECRET_VALUE_PATTERN"; then
        return 0
    fi
    return 1
}

# ── Variables système à ne jamais restaurer ───────────────────────────────────
# Ancré des deux côtés : sans ancrage, "PATH" happe PYTHONPATH/GOPATH/NODE_PATH
# et "HOME" happe JAVA_HOME — ces variables ne seraient jamais restaurées.
# LD_PRELOAD / LD_LIBRARY_PATH sont protégées parce que les importer depuis une
# autre machine casse (ou détourne) l'édition de liens dynamique.
MIGUATION_VARS_PROTEGEES='^(HOME|USER|LOGNAME|SHELL|PATH|TERM|DISPLAY|PWD|OLDPWD|SHLVL|IFS|PS1|PS2|PS3|PS4|EUID|UID|PPID|HOSTNAME|HOSTTYPE|OSTYPE|MACHTYPE|TMPDIR|TEMP|TMP|LANG|LANGUAGE|LC_[A-Z_]+|BASH.*|LD_PRELOAD|LD_LIBRARY_PATH|DYLD_.*|XDG_.*|SSH_.*|DBUS_.*|_)$'

# est_var_protegee NOM
est_var_protegee() {
    printf '%s' "$1" | grep -qE "$MIGUATION_VARS_PROTEGEES"
}

# ── Format du fichier de variables d'environnement ────────────────────────────
# Format : une ligne "NOM=valeur" par variable. Les valeurs multilignes ne sont
# pas représentables dans ce format et sont donc ignorées explicitement plutôt
# que de corrompre silencieusement les lignes suivantes à la relecture.
#
# ecrire_env_variables FICHIER_SORTIE FICHIER_SECRETS
# Lit l'environnement courant, écrit les variables propres, et liste les noms
# des secrets écartés dans FICHIER_SECRETS (les valeurs ne sont jamais écrites).
ecrire_env_variables() {
    local sortie="$1" fichier_secrets="$2" nom valeur
    : > "$sortie"
    : > "$fichier_secrets"
    # compgen -e énumère les variables exportées sans passer par un pipe, ce qui
    # évite le sous-shell qui faisait perdre la liste des secrets détectés.
    while IFS= read -r nom; do
        valeur="${!nom-}"
        if est_secret "$nom" "$valeur"; then
            printf '%s\n' "$nom" >> "$fichier_secrets"
        elif [ "$valeur" != "${valeur%$'\n'*}" ]; then
            printf '%s\n' "$nom (valeur multiligne, non exportable)" >> "$fichier_secrets"
        else
            printf '%s=%s\n' "$nom" "$valeur" >> "$sortie"
        fi
    done < <(compgen -e | sort)
}

# ── Détection de secrets dans les fichiers de configuration shell ─────────────
# Le filtre sur l'environnement ne sert à rien si l'on copie tel quel un .bashrc
# qui contient « export OPENAI_API_KEY=sk-… ». On signale ces lignes (nom de la
# variable et numéro de ligne uniquement, jamais la valeur).
#
# scanner_secrets_fichier FICHIER
# Écrit sur stdout « fichier:ligne:NOM » pour chaque affectation suspecte.
scanner_secrets_fichier() {
    local fichier="$1" base nom numero ligne
    [ -f "$fichier" ] || return 0
    base="$(basename "$fichier")"
    numero=0
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        numero=$((numero + 1))
        # export NOM=… / NOM=… / set -x NOM … (fish)
        nom="$(printf '%s' "$ligne" | sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p')"
        [ -n "$nom" ] || continue
        if est_secret "$nom"; then
            printf '%s:%s:%s\n' "$base" "$numero" "$nom"
        fi
    done < "$fichier"
}

# ── Parsing des listes de paquets ─────────────────────────────────────────────
# `dpkg --get-selections` produit « paquet<TAB>install ». L'ancien pipeline
# gardait la colonne 1 puis cherchait « :install » dedans — ce qui ne matchait
# jamais rien, donc aucun paquet n'était réinstallé.
dpkg_paquets_installes() {
    local fichier="$1"
    [ -f "$fichier" ] || return 0
    awk '$2 == "install" { print $1 }' "$fichier"
}

# snap_paquets FICHIER → « nom<TAB>classic|standard » (saute l'en-tête)
snap_paquets() {
    local fichier="$1"
    [ -f "$fichier" ] || return 0
    awk 'NR > 1 && NF > 0 {
        type = "standard"
        if ($0 ~ /classic/) { type = "classic" }
        print $1 "\t" type
    }' "$fichier"
}

# flatpak_paquets FICHIER → un identifiant d'application par ligne
# `flatpak list --columns=…` peut émettre un en-tête selon la version ; on le
# reconnaît par son libellé plutôt que de supposer un nombre de lignes fixe.
flatpak_paquets() {
    local fichier="$1"
    [ -f "$fichier" ] || return 0
    awk -F'\t' '{
        app = $1
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", app)
        if (app == "" || app == "Application" || app == "Application ID") { next }
        print app
    }' "$fichier"
}
