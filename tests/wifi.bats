#!/usr/bin/env bats
# Cohérence entre les scripts et sécurité du serveur de transfert.

setup() {
    RACINE="${BATS_TEST_DIRNAME}/.."
    source "$RACINE/scripts/lib/common.sh"
    TMP="$(mktemp -d)"
}

teardown() {
    [ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null
    rm -rf "$TMP"
}

# ── Régression n°4 : le SSID annoncé au client est celui que crée le serveur ──

@test "aucun script ne mentionne l'ancien nom de réseau Migratix" {
    # Régression : le commit de renommage a raté les scripts client, qui
    # demandaient de se connecter à « Migratix » — un réseau qui n'existe pas.
    run grep -ril "migratix" "$RACINE/scripts" "$RACINE/miguation.sh"
    [ -z "$output" ]
}

@test "le SSID est défini à un seul endroit et vaut Miguation" {
    [ "$MIGUATION_SSID" = "Miguation" ]
    # Le serveur bash doit tirer son SSID de la constante partagée, pas d'une
    # chaîne écrite en dur qui pourrait diverger à nouveau.
    grep -q 'SSID="\$MIGUATION_SSID"' "$RACINE/scripts/wifi-serveur.sh"
}

@test "les scripts PowerShell annoncent le même SSID que les scripts bash" {
    run grep -c "Miguation" "$RACINE/scripts/wifi-client.ps1"
    [ "$output" -ge 1 ]
    grep -q '\$ssid *= *"Miguation"' "$RACINE/scripts/wifi-serveur.ps1"
}

# ── Sécurité du serveur de transfert ─────────────────────────────────────────

demarrer_serveur() {
    printf 'contenu de la sauvegarde' | gzip > "$TMP/miguation.tar.gz"
    SOMME=$(sha256sum "$TMP/miguation.tar.gz" | cut -d' ' -f1)
    TOKEN="jetonDeTestAbcdef123456"
    PORT=8791
    python3 "$RACINE/scripts/lib/serveur.py" "$PORT" "$TOKEN" "$TMP/miguation.tar.gz" "$SOMME" &>/dev/null &
    SRV_PID=$!
    # attendre que le port réponde
    for _ in $(seq 1 40); do
        curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break
        sleep 0.1
    done
}

code_http() {
    curl -s -o /dev/null -w '%{http_code}' "$1"
}

@test "l'archive n'est pas accessible sans le token" {
    # Régression : `python3 -m http.server` servait tout le répertoire, donc
    # l'archive restait téléchargeable sur /miguation.tar.gz sans connaître le
    # token — et le listing du répertoire révélait le token lui-même.
    demarrer_serveur
    [ "$(code_http "http://127.0.0.1:$PORT/miguation.tar.gz")" = "404" ]
}

@test "le listing du répertoire n'est pas exposé" {
    demarrer_serveur
    [ "$(code_http "http://127.0.0.1:$PORT/")" = "404" ]
}

@test "un mauvais token est refusé" {
    demarrer_serveur
    [ "$(code_http "http://127.0.0.1:$PORT/mauvaisjeton/miguation.tar.gz")" = "404" ]
}

@test "la traversée de répertoire est refusée" {
    demarrer_serveur
    [ "$(code_http "http://127.0.0.1:$PORT/$TOKEN/../../etc/passwd")" != "200" ]
}

@test "le bon token donne accès à l'archive intacte" {
    demarrer_serveur
    run curl -s "http://127.0.0.1:$PORT/$TOKEN/miguation.tar.gz" --output "$TMP/recu.tar.gz"
    [ "$(sha256sum "$TMP/recu.tar.gz" | cut -d' ' -f1)" = "$SOMME" ]
}

@test "l'empreinte publiée correspond à l'archive servie" {
    demarrer_serveur
    run curl -s "http://127.0.0.1:$PORT/$TOKEN/miguation.tar.gz.sha256"
    [[ "$output" == "$SOMME"* ]]
}
