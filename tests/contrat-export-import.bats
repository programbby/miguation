#!/usr/bin/env bats
# Test de contrat bout-en-bout : ce que export.sh écrit, import.sh doit savoir
# le relire. C'est l'invariant central du projet — les deux scripts communiquent
# par un format de fichiers qui n'est spécifié nulle part ailleurs qu'ici.
#
# Chaque test s'exécute dans un faux dossier personnel : aucun fichier réel de
# l'utilisateur n'est lu ni écrit.

setup() {
    RACINE="${BATS_TEST_DIRNAME}/.."
    TMP="$(mktemp -d)"
    ANCIEN_PC="$TMP/ancien"
    NOUVEAU_PC="$TMP/nouveau"
    SAUVEGARDE="$TMP/sauvegarde"
    mkdir -p "$ANCIEN_PC" "$NOUVEAU_PC" "$SAUVEGARDE"

    # Contenu représentatif sur l'« ancien PC »
    mkdir -p "$ANCIEN_PC/Documents" "$ANCIEN_PC/Desktop" "$ANCIEN_PC/projets"
    echo "mon rapport" > "$ANCIEN_PC/Documents/rapport.txt"
    echo "note rapide" > "$ANCIEN_PC/Desktop/note.txt"
    echo "du code" > "$ANCIEN_PC/projets/main.py"
    # Un dossier qui doit être exclu de la copie
    mkdir -p "$ANCIEN_PC/projets/node_modules"
    echo "ballast" > "$ANCIEN_PC/projets/node_modules/paquet.js"

    export MIGUATION_NON_INTERACTIF=1
}

teardown() {
    rm -rf "$TMP"
}

# Lance export.sh avec un faux HOME et un environnement contrôlé.
lancer_export() {
    env -i \
        HOME="$ANCIEN_PC" \
        PATH="$PATH" \
        MIGUATION_NON_INTERACTIF=1 \
        "$@" \
        bash "$RACINE/scripts/export.sh" "$SAUVEGARDE" >/dev/null 2>&1
}

dossier_export() {
    find "$SAUVEGARDE" -maxdepth 1 -type d -name 'miguation_*' | head -1
}

# ── Le contrat de base ────────────────────────────────────────────────────────

@test "export produit une sauvegarde exploitable par import" {
    lancer_export
    EXPORT="$(dossier_export)"
    [ -n "$EXPORT" ]
    [ -f "$EXPORT/RAPPORT.txt" ]
    [ -f "$EXPORT/env_variables.txt" ]
    [ -d "$EXPORT/fichiers" ]
}

@test "les fichiers personnels font l'aller-retour intacts" {
    lancer_export
    EXPORT="$(dossier_export)"

    env -i HOME="$NOUVEAU_PC" PATH="$PATH" \
        bash "$RACINE/scripts/import.sh" "$EXPORT" >/dev/null 2>&1

    [ -f "$NOUVEAU_PC/Documents/rapport.txt" ]
    [ "$(cat "$NOUVEAU_PC/Documents/rapport.txt")" = "mon rapport" ]
    [ -f "$NOUVEAU_PC/Desktop/note.txt" ]
    [ -f "$NOUVEAU_PC/projets/main.py" ]
}

@test "node_modules est bien exclu de la sauvegarde" {
    lancer_export
    EXPORT="$(dossier_export)"
    [ ! -d "$EXPORT/fichiers/projets/node_modules" ]
}

# ── Régression n°1 : l'utilisateur est averti des secrets écartés ────────────

@test "un secret de l'environnement est écarté ET signalé dans le rapport" {
    lancer_export MON_SUPER_TOKEN="valeur-sensible" EDITOR="vim"
    EXPORT="$(dossier_export)"

    # écarté du fichier de variables…
    ! grep -q "MON_SUPER_TOKEN" "$EXPORT/env_variables.txt"
    ! grep -q "valeur-sensible" "$EXPORT/env_variables.txt"

    # …mais signalé à l'utilisateur, qui doit savoir quoi ressaisir.
    # Régression : la liste se perdait dans un sous-shell, le rapport était muet.
    grep -q "MON_SUPER_TOKEN" "$EXPORT/RAPPORT.txt"

    # la variable anodine, elle, est bien conservée
    grep -q "^EDITOR=vim$" "$EXPORT/env_variables.txt"
}

@test "la valeur d'un secret n'apparaît nulle part dans la sauvegarde" {
    lancer_export MON_API_KEY="sk-ne-doit-jamais-fuiter"
    EXPORT="$(dossier_export)"
    ! grep -rq "sk-ne-doit-jamais-fuiter" "$EXPORT"
}

@test "un secret en clair dans le .bashrc est signalé" {
    cat > "$ANCIEN_PC/.bashrc" <<'EOF'
export EDITOR=vim
export OPENAI_API_KEY=sk-en-clair-dans-le-bashrc
EOF
    lancer_export
    EXPORT="$(dossier_export)"

    # Le .bashrc est copié tel quel (l'utilisateur en a besoin), mais le rapport
    # doit dire que la sauvegarde contient un secret en clair.
    grep -q "OPENAI_API_KEY" "$EXPORT/RAPPORT.txt"
}

# ── Régression n°3 : les variables ne contenant PATH/HOME sont restaurées ────

@test "PYTHONPATH et JAVA_HOME survivent à l'aller-retour" {
    # Régression : la regex de protection n'était pas ancrée, donc PATH happait
    # PYTHONPATH et HOME happait JAVA_HOME. Ces variables disparaissaient
    # silencieusement pendant la migration.
    lancer_export PYTHONPATH="/opt/libs" JAVA_HOME="/usr/lib/jvm/17"
    EXPORT="$(dossier_export)"

    grep -q "^PYTHONPATH=/opt/libs$" "$EXPORT/env_variables.txt"
    grep -q "^JAVA_HOME=/usr/lib/jvm/17$" "$EXPORT/env_variables.txt"

    env -i HOME="$NOUVEAU_PC" PATH="$PATH" \
        bash "$RACINE/scripts/import.sh" "$EXPORT" >/dev/null 2>&1

    # Régression n°3b : import.sh faisait « export » dans un processus qui se
    # terminait aussitôt — rien n'était persisté, malgré le message « restaurées ».
    [ -f "$NOUVEAU_PC/.miguation_env" ]
    grep -q "PYTHONPATH" "$NOUVEAU_PC/.miguation_env"
    grep -q "JAVA_HOME" "$NOUVEAU_PC/.miguation_env"
}

@test "les variables système ne sont jamais écrasées à l'import" {
    lancer_export
    EXPORT="$(dossier_export)"

    env -i HOME="$NOUVEAU_PC" PATH="$PATH" \
        bash "$RACINE/scripts/import.sh" "$EXPORT" >/dev/null 2>&1

    [ -f "$NOUVEAU_PC/.miguation_env" ]
    ! grep -qE '^export (PATH|HOME|SHELL|LD_PRELOAD)=' "$NOUVEAU_PC/.miguation_env"
}

@test "import sauvegarde le .bashrc existant avant de l'écraser" {
    echo "export EDITOR=vim" > "$ANCIEN_PC/.bashrc"
    lancer_export
    EXPORT="$(dossier_export)"

    echo "ma config a moi" > "$NOUVEAU_PC/.bashrc"
    env -i HOME="$NOUVEAU_PC" PATH="$PATH" \
        bash "$RACINE/scripts/import.sh" "$EXPORT" >/dev/null 2>&1

    # L'ancienne config du nouveau PC ne doit pas être perdue.
    run bash -c "cat '$NOUVEAU_PC'/.bashrc.miguation-backup-* 2>/dev/null"
    [[ "$output" == *"ma config a moi"* ]]
}

# ── Non-destructivité ─────────────────────────────────────────────────────────

@test "import ne supprime pas les fichiers déjà présents sur le nouveau PC" {
    lancer_export
    EXPORT="$(dossier_export)"

    mkdir -p "$NOUVEAU_PC/Documents"
    echo "fichier deja la" > "$NOUVEAU_PC/Documents/existant.txt"

    env -i HOME="$NOUVEAU_PC" PATH="$PATH" \
        bash "$RACINE/scripts/import.sh" "$EXPORT" >/dev/null 2>&1

    [ -f "$NOUVEAU_PC/Documents/existant.txt" ]
    [ -f "$NOUVEAU_PC/Documents/rapport.txt" ]
}

# ── Contrat avec les scripts WiFi ─────────────────────────────────────────────

@test "export dépose le marqueur de chemin utilisé par wifi-serveur" {
    lancer_export
    [ -f "$SAUVEGARDE/.miguation-dernier-export" ]
    CHEMIN="$(cat "$SAUVEGARDE/.miguation-dernier-export")"
    [ -d "$CHEMIN" ]
    [ "$CHEMIN" = "$(dossier_export)" ]
}

@test "import refuse proprement un dossier source inexistant" {
    run env -i HOME="$NOUVEAU_PC" PATH="$PATH" \
        bash "$RACINE/scripts/import.sh" "$TMP/nexiste-pas"
    [ "$status" -ne 0 ]
    [[ "$output" == *"introuvable"* ]]
}
