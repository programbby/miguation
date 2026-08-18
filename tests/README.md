# Tests

## Lancer les tests

```bash
# Dépendances
sudo apt install bats shellcheck rsync     # Debian/Ubuntu
brew install bats-core shellcheck rsync    # macOS

# Toute la suite
bats tests/

# Un seul fichier
bats tests/secrets.bats
```

Analyse statique :

```bash
LC_ALL=C.UTF-8 shellcheck -x -S warning miguation.sh scripts/*.sh scripts/lib/common.sh
```

## Organisation

| Fichier | Couvre |
|---|---|
| `secrets.bats` | Filtrage des secrets, détection dans les fichiers shell |
| `paquets.bats` | Parsing des listes dpkg / snap / flatpak, variables protégées |
| `contrat-export-import.bats` | Aller-retour complet export → import dans un faux `$HOME` |
| `wifi.bats` | Cohérence du SSID entre scripts, sécurité du serveur de transfert |

Aucun test ne lit ni n'écrit dans le vrai dossier personnel : `contrat-export-import.bats`
fabrique un « ancien PC » et un « nouveau PC » sous `mktemp -d` et lance les scripts
avec `env -i HOME=…`.

## Régressions verrouillées

Ces tests existent parce que les bugs correspondants étaient présents en production.
Chacun échoue si le bug revient.

1. **Liste des secrets perdue dans un sous-shell** — `export.sh` construisait la liste
   des variables sensibles derrière un pipe, donc dans un sous-shell. Le tableau était
   toujours vide : l'utilisateur n'était jamais averti de ce qu'il devait ressaisir.
   → `secrets.bats`, `contrat-export-import.bats`

2. **Aucun paquet Debian réinstallé** — `awk '{print $1}' | grep ':install$'` cherchait
   `:install` dans la colonne du nom de paquet, où il n'apparaît jamais. Le filtre
   éliminait tout, mais le script affichait « paquets restaurés ».
   → `paquets.bats`

3. **Variables silencieusement perdues** — la regex des variables protégées n'était pas
   ancrée : `PATH` happait `PYTHONPATH`/`GOPATH`/`NODE_PATH`, `HOME` happait `JAVA_HOME`.
   Ces variables n'étaient jamais restaurées. Et `import.sh` faisait `export` dans un
   processus qui se terminait aussitôt, donc rien n'était persisté du tout.
   → `paquets.bats`, `contrat-export-import.bats`

4. **SSID incohérent** — les scripts client demandaient de se connecter à « Migratix »
   alors que le serveur crée « Miguation ». Le renommage avait raté ces fichiers.
   → `wifi.bats`

5. **Token de transfert contournable** — `python3 -m http.server` publiait tout le
   répertoire : l'archive était accessible sans le token, et le listing révélait le
   token. Remplacé par un serveur qui ne répond que sur la route tokenisée.
   → `wifi.bats`
