#!/usr/bin/env bats
# Filtrage des secrets — la fonction la plus critique du projet.
# Un faux négatif fait fuiter une clé sur une clé USB ; un faux positif prive
# l'utilisateur d'une variable dont il a besoin.

setup() {
    source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"
    TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP"
}

# ── Faux négatifs : ces variables DOIVENT être écartées ───────────────────────

@test "est_secret détecte les noms de secrets courants" {
    for nom in MY_API_KEY GITHUB_TOKEN AWS_SECRET_ACCESS_KEY DB_PASSWORD \
               SSH_PRIVATE_KEY OAUTH_CLIENT_ID NPM_AUTH_TOKEN STRIPE_API_KEY \
               JWT_SIGNING_KEY GITHUB_PAT SESSION_SECRET; do
        run est_secret "$nom"
        [ "$status" -eq 0 ] || {
            echo "FUITE : $nom n'est pas reconnu comme secret"
            return 1
        }
    done
}

@test "est_secret détecte un mot de passe dans une URL de connexion" {
    run est_secret "DATABASE_URL" "postgres://admin:hunter2@db.interne/prod"
    [ "$status" -eq 0 ]
}

# ── Faux positifs : ces variables doivent être CONSERVÉES ─────────────────────

@test "est_secret ne se déclenche pas sur des noms anodins" {
    # Régression : l'ancien motif non délimité faisait matcher PASS dans COMPASS,
    # API dans RAPID et KEY dans MONKEY.
    for nom in COMPASS_HOME RAPID_TIMEOUT MONKEY_MODE JAVA_HOME EDITOR \
               LANG GOPATH NODE_ENV TERM_PROGRAM; do
        run est_secret "$nom"
        [ "$status" -ne 0 ] || {
            echo "FAUX POSITIF : $nom est pris pour un secret"
            return 1
        }
    done
}

@test "est_secret ne se déclenche pas sur une URL sans identifiants" {
    run est_secret "DATABASE_URL" "postgres://db.interne/prod"
    [ "$status" -ne 0 ]
}

# ── Bug de régression n°1 : la liste des secrets survit à la boucle ───────────

@test "ecrire_env_variables retourne la liste des secrets (pas de sous-shell)" {
    # Régression : la boucle tournait derrière un pipe, donc dans un sous-shell.
    # Le tableau des secrets était toujours vide et l'utilisateur n'était jamais
    # averti de ce qu'il devait ressaisir.
    export TEST_SUPER_TOKEN="valeur-sensible"
    export TEST_VARIABLE_NORMALE="valeur-ok"

    ecrire_env_variables "$TMP/env.txt" "$TMP/secrets.txt"

    grep -q "^TEST_SUPER_TOKEN$" "$TMP/secrets.txt"
    grep -q "^TEST_VARIABLE_NORMALE=valeur-ok$" "$TMP/env.txt"

    unset TEST_SUPER_TOKEN TEST_VARIABLE_NORMALE
}

@test "ecrire_env_variables n'écrit jamais la valeur d'un secret" {
    export TEST_SECRET_TOKEN="ne-doit-jamais-apparaitre"

    ecrire_env_variables "$TMP/env.txt" "$TMP/secrets.txt"

    ! grep -q "ne-doit-jamais-apparaitre" "$TMP/env.txt"
    ! grep -q "ne-doit-jamais-apparaitre" "$TMP/secrets.txt"

    unset TEST_SECRET_TOKEN
}

@test "ecrire_env_variables ignore les valeurs multilignes au lieu de corrompre le fichier" {
    # Une valeur multiligne écrite telle quelle casse la relecture ligne à ligne
    # de import.sh : toutes les lignes suivantes deviennent des variables bidon.
    export TEST_VAR_MULTILIGNE="ligne1
ligne2"
    export TEST_VAR_APRES="intacte"

    ecrire_env_variables "$TMP/env.txt" "$TMP/secrets.txt"

    ! grep -q "^ligne2$" "$TMP/env.txt"
    grep -q "^TEST_VAR_APRES=intacte$" "$TMP/env.txt"

    unset TEST_VAR_MULTILIGNE TEST_VAR_APRES
}

# ── Secrets en clair dans les fichiers shell ──────────────────────────────────

@test "scanner_secrets_fichier repère un secret exporté dans un .bashrc" {
    # Filtrer l'environnement ne sert à rien si on copie tel quel un .bashrc
    # contenant « export OPENAI_API_KEY=… ».
    cat > "$TMP/.bashrc" <<'EOF'
export EDITOR=vim
export OPENAI_API_KEY=sk-valeur-tres-secrete
alias ll='ls -la'
EOF

    run scanner_secrets_fichier "$TMP/.bashrc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPENAI_API_KEY"* ]]
    [[ "$output" != *"sk-valeur-tres-secrete"* ]]  # la valeur ne doit jamais fuiter
    [[ "$output" != *"EDITOR"* ]]
}

@test "scanner_secrets_fichier indique le numéro de ligne" {
    printf 'export EDITOR=vim\nexport GITHUB_TOKEN=ghp_xxx\n' > "$TMP/.zshrc"
    run scanner_secrets_fichier "$TMP/.zshrc"
    [[ "$output" == *":2:GITHUB_TOKEN"* ]]
}

@test "scanner_secrets_fichier accepte un fichier absent" {
    run scanner_secrets_fichier "$TMP/nexiste-pas"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
