# coffre

`coffre` met en place, ouvre et ferme un environnement sécurisé destiné à stocker des
configurations et des clés SSH/GPG. Le conteneur est un **fichier de 5 Go**, chiffré avec
**LUKS2** et formaté en **ext4**, monté à la demande dans `~/.coffre`.

## Arborescence

```
coffre/
├── bin/
│   └── coffre          # lanceur (à rendre exécutable)
└── lib/
    ├── core.sh         # chemins globaux + helpers (erreur, confirmations)
    ├── state.sh        # détection de l'état du coffre
    ├── vault.sh        # install / open / close (LUKS + ext4)
    ├── gpgops.sh       # génération, export et import GPG
    └── sshops.sh       # template SSH, alias, import par host
```

Le lanceur `bin/coffre` source les fichiers de `lib/`. Conservez cette disposition
(`bin/` et `lib/` côte à côte).

## Prérequis

Outils attendus : `sudo`, `cryptsetup`, `mkfs.ext4`, `mount`/`umount`, `findmnt`, `gpg`,
`ssh`, `ssh-keygen`, `awk`, `install`, `mktemp`, `dd`. Des droits `sudo` sont nécessaires
pour les opérations LUKS et le montage.

```bash
chmod +x bin/coffre
```

## États et permissions

| Élément                       | Chemin                                 | Permissions |
|-------------------------------|----------------------------------------|-------------|
| Conteneur chiffré             | `~/.local/share/coffre/conteneur.luks` | `600`       |
| Point de montage              | `~/.coffre`                            | `700`       |
| Répertoires internes du coffre| `~/.coffre/ssh`, `.../gpg`, ...        | `700`       |
| Config SSH du coffre          | `~/.coffre/ssh/config`                 | `600`       |
| Clés SSH privées importées    | `~/.coffre/ssh/cles/*`                 | `600`       |
| Clés SSH publiques importées  | `~/.coffre/ssh/cles/*.pub`             | `644`       |
| Export GPG public             | `~/.coffre/gpg/publiques/*.pub.asc`    | `644`       |
| Export GPG privé              | `~/.coffre/gpg/privees/*.sec.asc`      | `400`       |
| Lien symbolique + alias       | `~/.config/coffre/ssh-config`, `alias.sh` | `700` / `644` |

Le volume est monté avec `nodev,nosuid`.

## Utilisation

### Cycle de vie (Part I / Part IV)

```bash
coffre install     # crée le conteneur de 5 Go (dd), LUKS2, ext4, puis le referme
coffre open        # déverrouille (luksOpen) et monte le coffre dans ~/.coffre
coffre close       # démonte et referme (luksClose)
```

`install` refuse de s'exécuter si un coffre existe déjà. `open` et `close` sont
idempotents. La phrase secrète LUKS est demandée de façon interactive par `cryptsetup`.

### GPG (Part II / Part IV)

```bash
coffre gpg generate                  # paire ed25519/cv25519, export auto de la clé publique dans le coffre
coffre gpg export-pub  <id>          # trousseau -> coffre (clé publique)
coffre gpg export-priv <id>          # trousseau -> coffre (clé privée, confirmation "EXPORTER")
coffre gpg import-pub  <id|fichier>  # coffre -> trousseau (clé publique)
coffre gpg import-priv <id|fichier>  # coffre -> trousseau (clé privée)
```

L'export de clé privée est prévu **uniquement pour un changement de poste** : le fichier
est écrit en `400`, protégé par la phrase secrète de la clé, et doit être supprimé du
coffre une fois la migration terminée.

### SSH (Part III)

```bash
coffre ssh template        # config SSH type dans le coffre (utilisable avec -F) + alias + lien symbolique
coffre ssh import [host]    # importe un host depuis ~/.ssh/config (sans argument : menu de sélection)
```

`ssh import` recopie le bloc du host choisi dans le coffre, copie la paire de clés
associée dans `~/.coffre/ssh/cles/`, et réécrit la ligne `IdentityFile` pour pointer vers
la clé copiée.

Après `ssh template`, chargez l'alias puis utilisez-le :

```bash
source ~/.config/coffre/alias.sh
evsh <host>        # équivaut à : ssh -F ~/.config/coffre/ssh-config <host>
```

Pour un chargement permanent, ajoutez `source ~/.config/coffre/alias.sh` à votre `~/.bashrc`.

## Comportement

- Succès **silencieux** (aucun message). Les erreurs vont sur la sortie d'erreur, préfixées
  `coffre:`. Code de sortie : `0` en cas de succès, `1` en cas d'erreur.
- Aucun nettoyage automatique : si `install` échoue en cours de route, supprimez
  manuellement le conteneur (`~/.local/share/coffre/conteneur.luks`) et, si besoin, fermez
  le mapper resté ouvert (`sudo cryptsetup luksClose coffre-$(id -un)`) avant de relancer.

## Tests manuels

Le projet ne contient pas de script de test automatique ; la vérification est laissée à
l'utilisateur. Exemples de contrôles :

```bash
coffre install
stat -c '%a' ~/.local/share/coffre/conteneur.luks   # 600
coffre open
stat -c '%a' ~/.coffre/ssh                            # 700
coffre ssh template
readlink ~/.config/coffre/ssh-config                  # -> ~/.coffre/ssh/config
coffre gpg generate
ls ~/.coffre/gpg/publiques/                           # export public présent
coffre close
```
