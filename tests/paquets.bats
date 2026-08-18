#!/usr/bin/env bats
# Parsing des listes de paquets — contrat implicite entre export.sh et import.sh.
# Ces formats ne sont écrits nulle part ailleurs : ces tests en sont la spécification.

setup() {
    source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"
    TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP"
}

# ── Bug de régression n°2 : le pipeline dpkg ne renvoyait jamais rien ─────────

@test "dpkg_paquets_installes lit le format réel de dpkg --get-selections" {
    # Régression : « awk '{print \$1}' | grep ':install\$' » cherchait ':install'
    # dans la colonne du nom de paquet — ce qui ne matche jamais. Résultat :
    # aucun paquet n'était réinstallé, alors que le script affichait « OK ».
    printf 'firefox\tinstall\nvim\tinstall\ngit\tinstall\n' > "$TMP/dpkg.txt"

    run dpkg_paquets_installes "$TMP/dpkg.txt"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[0]}" = "firefox" ]
    [ "${lines[2]}" = "git" ]
}

@test "dpkg_paquets_installes exclut les paquets deinstall" {
    printf 'firefox\tinstall\nnano\tdeinstall\nvim\tinstall\n' > "$TMP/dpkg.txt"
    run dpkg_paquets_installes "$TMP/dpkg.txt"
    [ "${#lines[@]}" -eq 2 ]
    [[ "$output" != *"nano"* ]]
}

@test "dpkg_paquets_installes gère les espaces multiples comme séparateur" {
    printf 'firefox    install\nvim\tinstall\n' > "$TMP/dpkg.txt"
    run dpkg_paquets_installes "$TMP/dpkg.txt"
    [ "${#lines[@]}" -eq 2 ]
}

@test "dpkg_paquets_installes accepte un fichier absent" {
    run dpkg_paquets_installes "$TMP/nexiste-pas"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ── snap ──────────────────────────────────────────────────────────────────────

@test "snap_paquets saute l'en-tête et distingue les snaps classic" {
    cat > "$TMP/snap.txt" <<'EOF'
Name      Version  Rev  Tracking  Publisher  Notes
code      1.85     150  latest    microsoft  classic
spotify   1.2.0    70   latest    spotify    -
EOF
    run snap_paquets "$TMP/snap.txt"
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" == "code"*"classic" ]]
    [[ "${lines[1]}" == "spotify"*"standard" ]]
    [[ "$output" != *"Name"* ]]
}

# ── flatpak ───────────────────────────────────────────────────────────────────

@test "flatpak_paquets ignore l'en-tête quelle que soit la version de flatpak" {
    # Selon la version, `flatpak list --columns=…` émet ou non un en-tête.
    # L'ancien code faisait « tail -n +1 », qui n'en retirait aucun : le libellé
    # « Application » était alors passé à flatpak install comme un paquet.
    printf 'Application\tBranch\norg.gimp.GIMP\tstable\n' > "$TMP/avec.txt"
    printf 'org.gimp.GIMP\tstable\n' > "$TMP/sans.txt"

    run flatpak_paquets "$TMP/avec.txt"
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "org.gimp.GIMP" ]

    run flatpak_paquets "$TMP/sans.txt"
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "org.gimp.GIMP" ]
}

# ── Bug de régression n°3 : variables protégées ──────────────────────────────

@test "est_var_protegee protège les variables système" {
    for nom in PATH HOME USER SHELL LD_PRELOAD LD_LIBRARY_PATH PWD LC_ALL; do
        run est_var_protegee "$nom"
        [ "$status" -eq 0 ] || {
            echo "DANGER : $nom serait écrasée par la sauvegarde"
            return 1
        }
    done
}

@test "est_var_protegee ne happe pas les variables contenant PATH ou HOME" {
    # Régression : la regex n'était pas ancrée, donc PATH matchait PYTHONPATH,
    # GOPATH et NODE_PATH, et HOME matchait JAVA_HOME. Ces variables n'étaient
    # jamais restaurées, sans le moindre message.
    for nom in PYTHONPATH GOPATH NODE_PATH JAVA_HOME MAVEN_HOME ANDROID_HOME \
               CARGO_HOME MA_VARIABLE_PERSO; do
        run est_var_protegee "$nom"
        [ "$status" -ne 0 ] || {
            echo "PERDUE : $nom ne serait jamais restaurée"
            return 1
        }
    done
}
