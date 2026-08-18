# Miguation

Outil de migration d'ordinateur personnel. Copie tes fichiers, tes marque-pages,
la liste de tes logiciels et tes variables d'environnement d'une machine vers une
autre — par clé USB ou par WiFi direct, sans passer par le cloud.

Fonctionne sur **Windows**, **macOS** et **Linux**. Les migrations entre systèmes
différents sont possibles, avec des limites précisées plus bas.

---

## À quoi ça sert

- **Tu changes d'ordinateur.** Tu veux retrouver tes documents, tes marque-pages et
  tes outils sans tout refaire à la main.
- **Tu réinstalles ton système.** Tu sauvegardes avant, tu restaures après.
- **Tu passes de Windows à Linux** (ou l'inverse). Les chemins et les gestionnaires
  de paquets sont différents : Miguation fait la correspondance.
- **Tu n'as pas de réseau.** Le mode WiFi crée un point d'accès direct entre les deux
  machines : rien ne transite par Internet.

Ce n'est **pas** un outil de sauvegarde continue ni un clone disque. C'est un
transfert ponctuel de ce qui compte pour un utilisateur.

---

## Démarrage rapide

### Linux / macOS

```bash
git clone https://github.com/programbby/miguation.git
cd miguation
chmod +x miguation.sh
./miguation.sh
```

Un menu propose les quatre opérations. Lance avec `sudo` pour une copie complète
(certains fichiers appartiennent à root).

### Windows

Double-clique sur le fichier correspondant à ce que tu veux faire — chacun demande
les droits administrateur :

| Fichier | Rôle |
|---|---|
| `exporter.bat` | Sauvegarder cet ordinateur vers un dossier ou une clé USB |
| `importer.bat` | Restaurer une sauvegarde sur cet ordinateur |
| `transfert-wifi-serveur.bat` | Envoyer par WiFi (**ancien** PC) |
| `transfert-wifi-client.bat` | Recevoir par WiFi (**nouveau** PC) |

---

## Les deux modes de transfert

### Par clé USB (ou dossier partagé)

```
ANCIEN PC                          NOUVEAU PC
  export  ──►  dossier miguation_AAAA-MM-JJ_HH-MM  ──►  import
```

Le dossier produit est autonome et lisible : tu peux l'inspecter avant de restaurer.

### Par WiFi direct

L'ancien PC crée un point d'accès nommé **Miguation**, avec un mot de passe généré
aléatoirement à chaque lancement. Le nouveau PC s'y connecte et récupère l'archive.
Aucun routeur, aucun serveur externe.

Le mécanisme diffère selon la plateforme :

| | Linux / macOS | Windows |
|---|---|---|
| Point d'accès | `nmcli` (Linux) ou manuel (macOS) | API WinRT, sinon `netsh`, sinon manuel |
| Transport | HTTP sur port 8765, URL tokenisée | Partage SMB `mgx-share` |
| Contrôle d'accès | Token aléatoire de 24 caractères dans l'URL | Compte local temporaire `mgx-tmp`, lecture seule |
| Intégrité | SHA256 vérifié par le client | — (SMB gère l'intégrité) |

Dans les deux cas, tout est démonté au moment où le script se termine : point
d'accès éteint, partage fermé, compte temporaire supprimé, archive et dossier
temporaire effacés.

---

## Ce qui est migré

### Fichiers personnels

| Source (Linux/macOS) | Source (Windows) | Nom dans la sauvegarde |
|---|---|---|
| `~/Documents` | `%USERPROFILE%\Documents` | `Documents` |
| `~/Desktop` | `%USERPROFILE%\Desktop` | `Bureau` |
| `~/Pictures` | `%USERPROFILE%\Pictures` | `Images` |
| `~/Movies` | `%USERPROFILE%\Videos` | `Videos` |
| `~/Music` | `%USERPROFILE%\Music` | `Musique` |
| `~/Downloads` | `%USERPROFILE%\Downloads` | `Telechargements` |
| `~/projets` | `%USERPROFILE%\projets` | `projets` |
| `~/.claude` | `%USERPROFILE%\.claude` | `.claude` |

Les dossiers de dépendances et d'artefacts sont exclus, ils se régénèrent :
`node_modules`, `.venv`, `__pycache__`, `.cache`, `.git`, `dist`, `build`, `.next`,
`vendor`, `*.tmp`, `Thumbs.db`.

### Navigateurs

| Navigateur | Ce qui est copié |
|---|---|
| Chrome, Edge, Brave | Marque-pages + **liste** des extensions |
| Firefox | Profil complet (`profiles.ini` inclus) |
| Safari (macOS) | Marque-pages |

### Logiciels

Miguation exporte la **liste** des logiciels installés, et la réinstalle quand le
gestionnaire de paquets le permet :

| Gestionnaire | Exporté | Réinstallé automatiquement |
|---|---|---|
| winget (Windows) | ✅ | ✅ |
| Homebrew (macOS) | ✅ formulas et casks séparés | ✅ |
| Mac App Store (`mas`) | ✅ | ✅ |
| apt / dpkg (Debian, Ubuntu) | ✅ | ✅ |
| snap | ✅ | ✅ (les snaps `classic` sont gérés) |
| flatpak | ✅ | ✅ |
| **rpm (Fedora, RHEL)** | ✅ | ❌ **liste seulement** |
| Registre Windows | ✅ (`liste_complete.csv`) | ❌ liste seulement |
| `/Applications` (macOS) | ✅ | ❌ liste seulement |

### Variables d'environnement

Les variables sont exportées **sauf celles qui ressemblent à des secrets** (voir
plus bas). Les fichiers `.bashrc`, `.zshrc`, `.bash_profile` et `.profile` sont
copiés tels quels.

À la restauration, elles sont écrites dans `~/.miguation_env`, chargé automatiquement
par ton shell (une ligne est ajoutée à `.bashrc`/`.zshrc`). Elles deviennent actives
au prochain terminal ouvert. Sur Windows, elles sont écrites dans l'environnement
utilisateur du registre.

---

## Ce qui n'est PAS migré

C'est aussi important que le reste :

- **Les mots de passe des navigateurs.** Active la synchronisation du navigateur
  (Paramètres → Synchronisation) : c'est plus sûr et ça marche mieux.
- **Les extensions de navigateur elles-mêmes.** Seule la liste est transférée — tu les
  réinstalles depuis le store. Sous Windows la liste contient le nom lisible de chaque
  extension ; sous Linux/macOS, seulement son identifiant.
- **Les secrets détectés dans l'environnement.** Volontairement (voir ci-dessous).
  Le rapport te dit lesquels ressaisir.
- **Les paquets rpm.** Exportés dans `logiciels/rpm.txt` mais jamais réinstallés :
  sur Fedora/RHEL, la restauration des logiciels est à faire à la main.
- **Les licences logicielles**, les clés d'activation, les données d'applications
  hors des dossiers listés plus haut.

---

## Migrer entre deux systèmes différents

Une sauvegarde faite sous Linux se restaure sur un Windows, mais **tout ne traverse
pas**. Les deux implémentations n'écrivent pas les mêmes fichiers pour tout :

| Élément | Windows ↔ Linux/macOS |
|---|---|
| Fichiers personnels | ✅ format identique |
| Marque-pages Chrome / Edge / Brave | ✅ format identique |
| Profil Firefox | ✅ format identique |
| `RAPPORT.txt`, journal | ✅ |
| **Variables d'environnement** | ❌ `env_variables.txt` (bash) vs `env_variables.json` (PowerShell) |
| **Liste des extensions** | ❌ `extensions.txt` (bash) vs `extensions.csv` (PowerShell) |
| Listes de logiciels | ❌ par nature — winget, brew et apt ne sont pas interchangeables |

Concrètement : d'un Linux vers un Windows, tes fichiers et tes marque-pages arrivent,
mais tes variables d'environnement doivent être ressaisies. Elles restent lisibles
dans `env_variables.txt` à l'intérieur de la sauvegarde.

C'est une limite de l'implémentation actuelle, pas une contrainte technique : unifier
le format des variables et des extensions rendrait la migration croisée complète.

---

## Sécurité

### Filtrage des secrets

Une variable d'environnement est écartée de la sauvegarde si son **nom** évoque un
secret (`SECRET`, `TOKEN`, `PASSWORD`, `CREDENTIAL`, `PRIVATE`, `OAUTH`, ou les mots
`KEY`, `API`, `AUTH`, `PASS`, `PAT`, `SALT`, `SIG`, `CERT`, `SESSION`, `COOKIE`
délimités par `_`), ou si sa **valeur** contient des identifiants dans une URL
(`postgres://user:motdepasse@hote`).

Les noms écartés te sont affichés et listés dans `RAPPORT.txt` — jamais leurs valeurs.

### Limite connue, et assumée

Tes fichiers `.bashrc` / `.zshrc` sont **copiés tels quels**, car tu en as besoin sur
le nouveau PC. S'ils contiennent `export OPENAI_API_KEY=sk-...`, ce secret **est dans
la sauvegarde**. Miguation ne peut pas les expurger sans casser ta configuration.

Ce qu'il fait à la place : il **détecte ces lignes et te prévient**, en te donnant le
fichier, le numéro de ligne et le nom de la variable (jamais la valeur). Le message
apparaît à l'export et dans `RAPPORT.txt`.

> **Traite toute sauvegarde Miguation comme un document confidentiel.** Elle contient
> tes fichiers personnels, tes marque-pages et potentiellement des secrets en clair.

### Variables système protégées

À la restauration, certaines variables ne sont **jamais** écrasées, parce que les
importer depuis une autre machine casserait le système : `PATH`, `HOME`, `SHELL`,
`LD_PRELOAD`, `LD_LIBRARY_PATH`, les `LC_*`, les `XDG_*`, les `SSH_*`, et leurs
équivalents Windows.

En revanche `PYTHONPATH`, `GOPATH`, `JAVA_HOME`, `CARGO_HOME` et consorts **sont**
restaurés : ce sont des variables utilisateur légitimes.

### Non-destructivité

- La restauration utilise `rsync` **sans** `--delete` : rien n'est supprimé sur le
  nouveau PC, les fichiers existants sont conservés.
- Un `.bashrc` déjà présent est sauvegardé en `.bashrc.miguation-backup-<horodatage>`
  avant d'être remplacé.
- Si `rsync` est absent, l'export **refuse de démarrer** plutôt que de produire une
  sauvegarde vide en annonçant un succès.

---

## Architecture

```
miguation/
├── miguation.sh                  Menu unique — Linux / macOS
├── exporter.bat                  Points d'entrée Windows :
├── importer.bat                    chacun lance le .ps1 correspondant
├── transfert-wifi-serveur.bat      avec -ExecutionPolicy Bypass
├── transfert-wifi-client.bat
│
├── scripts/
│   ├── lib/
│   │   ├── common.sh             Constantes + fonctions pures (sans effet de bord)
│   │   └── serveur.py            Serveur HTTP restreint à la route tokenisée
│   │
│   ├── export.sh    export.ps1   Machine → dossier de sauvegarde
│   ├── import.sh    import.ps1   Dossier de sauvegarde → machine
│   ├── wifi-serveur.sh  .ps1     Export + point d'accès + serveur
│   └── wifi-client.sh   .ps1     Connexion + téléchargement + import
│
└── tests/                        39 tests bats — voir tests/README.md
```

### Deux implémentations parallèles

Chaque opération existe en **bash** (Linux/macOS) et en **PowerShell** (Windows).
Ce n'est pas de la duplication gratuite : les deux mondes n'ont ni les mêmes chemins,
ni les mêmes gestionnaires de paquets, ni les mêmes API réseau.

Le risque, c'est la **dérive** entre les deux — c'est déjà arrivé. Les points qui
doivent rester synchronisés sont signalés par un commentaire dans le code et
couverts par des tests :

- le motif de détection des secrets (`MIGUATION_SECRET_PATTERN` ↔ `$secretPattern`) ;
- la liste des variables système protégées ;
- le nom du réseau WiFi (`MIGUATION_SSID` ↔ `$ssid`).

### Flux de données

```
export.sh ──écrit──► dossier de sauvegarde ──lit──► import.sh
                            │
                            └── le format de ce dossier est le contrat
                                entre les deux scripts. Il est spécifié
                                par tests/contrat-export-import.bats.
```

Les scripts WiFi ne réimplémentent rien : `wifi-serveur.sh` appelle `export.sh` puis
sert le résultat ; `wifi-client.sh` télécharge puis appelle `import.sh`.

---

## Format d'une sauvegarde

```
miguation_2026-08-18_16-42/
├── RAPPORT.txt              Résumé + actions manuelles à faire
├── miguation.log            Journal détaillé (erreurs de copie)
├── env_variables.txt        NOM=valeur, une par ligne (.json sous Windows)
├── secrets_ignores.txt      Noms des secrets écartés — jamais les valeurs
├── secrets_en_clair.txt     Secrets repérés dans les .bashrc/.zshrc copiés
├── .bashrc .zshrc …         Fichiers de configuration shell, tels quels
│
├── fichiers/
│   ├── Documents/  Bureau/  Images/  Videos/
│   └── Musique/  Telechargements/  projets/  .claude/
│
├── navigateurs/
│   ├── Chrome/     Bookmarks + extensions.txt (.csv sous Windows)
│   ├── Edge/  Brave/
│   ├── Firefox/    Profiles/ + profiles.ini
│   └── Safari/     Bookmarks.plist
│
└── logiciels/
    ├── winget.json  liste_complete.csv          (Windows)
    ├── brew-formulas.txt  brew-casks.txt        (macOS)
    ├── appstore.txt  applications.txt           (macOS)
    └── dpkg.txt  rpm.txt  snap.txt  flatpak.txt (Linux)
```

`env_variables.txt` utilise un format `NOM=valeur` d'une ligne par variable. Les
valeurs multilignes ne sont pas représentables et sont donc écartées explicitement,
avec une mention dans `secrets_ignores.txt` — plutôt que de corrompre silencieusement
la relecture.

---

## Développement

```bash
# Tests
bats tests/

# Analyse statique
LC_ALL=C.UTF-8 shellcheck -x -S warning miguation.sh scripts/*.sh scripts/lib/common.sh
```

La CI (`.github/workflows/ci.yml`) exécute `shellcheck`, `bats`, `py_compile` et
`PSScriptAnalyzer` à chaque push.

**Toute logique testable va dans `scripts/lib/common.sh`.** Ce fichier n'a aucun effet
de bord : il peut être sourcé par les tests. Les scripts principaux s'occupent des
effets de bord (copie, réseau, affichage) et délèguent les décisions à la lib.

`tests/README.md` documente les cinq régressions verrouillées par la suite de tests —
des bugs qui étaient réellement en production.

---

## Limites connues

- **Les correctifs PowerShell ne sont pas vérifiés par exécution.** La CI lance
  `PSScriptAnalyzer` (analyse statique), mais la suite `bats` ne couvre que les
  scripts bash. Une validation sur une vraie machine Windows reste à faire.
- **rpm n'est pas restauré** (Fedora, RHEL, openSUSE).
- **Le point d'accès WiFi n'est pas automatisable sur macOS** : le script affiche le
  nom et le mot de passe, puis attend que tu l'actives dans les Réglages Système.
- **Le client WiFi Windows suppose l'adresse `192.168.137.1`**, valeur par défaut du
  partage de connexion Windows. Une configuration réseau différente demandera une
  saisie manuelle.
- **Le profil Firefox est copié tel quel.** Selon les versions de Firefox en jeu, un
  profil venant d'une version plus récente peut être refusé par une plus ancienne.
