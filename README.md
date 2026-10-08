# SentiNet — Stack Docker

Conteneurisation du projet **NetSentinel**, un outil de détection réseau assistée
par machine learning (projet YDays — Ynov Campus Toulouse). Le dossier s'appelle
`SentiNet`, le produit *NetSentinel* : c'est le même projet.

## Services

Toutes les images sont construites depuis l'unique `dockerfile` multi-stage.
Seul le reverse proxy expose un port sur l'hôte.

| Service | Image de base | URL | Rôle |
| --- | --- | --- | --- |
| `nginx-proxy` | `sysadminmichael/sentinet:nginx-1.27-alpine-slim` | port 80 | Reverse proxy par nom de domaine |
| `web` | `sysadminmichael/sentinet:nginx-1.27-alpine-slim` | <http://netsentinel.localhost> | Site vitrine statique |
| `app` | `sysadminmichael/sentinet:matomo-5-apache` | <http://matomo.localhost> | Analytics auto-hébergé |
| `db` | `sysadminmichael/sentinet:db-12.3.3` | interne | Base de Matomo |
| `wordpress` | `wordpress:6-apache` | <http://wp.localhost> | WordPress |
| `wp-db` | `sysadminmichael/sentinet:db-12.3.3` | interne | Base de WordPress |

Réseaux :

- `front` relie le proxy au site, à Matomo et à WordPress.
- `back` est interne (pas d'accès Internet) et relie les applications à leurs bases.

`app` et `wordpress` attendent que leur base soit *healthy* avant de démarrer.

## Démarrage

Prérequis : Docker Engine (ou Docker Desktop) avec le plugin Compose, le
port 80 libre sur la machine, et un accès au registre privé `sysadminmichael`.

```bash
cd SentiNet
docker login                  # compte ayant accès au registre privé
cp .env.example .env          # puis remplacer chaque "changeme"
docker compose up -d --build
docker compose ps             # attendre que tout soit "healthy" / "running"
```

Les noms `*.localhost` pointent automatiquement vers 127.0.0.1 dans Chrome,
Firefox et curl. Sinon, ajouter dans `/etc/hosts` :

```text
127.0.0.1 netsentinel.localhost matomo.localhost wp.localhost
```

Au premier lancement, Matomo et WordPress affichent un assistant d'installation.
Pour Matomo, déclarer le site `http://netsentinel.localhost` : il recevra l'ID 1,
celui utilisé par le traceur de `site/index.html`.

Vérifier la sonde de santé du site :

```bash
curl http://netsentinel.localhost/healthz    # doit répondre "ok"
```

Arrêter la stack :

```bash
docker compose down        # conserve les données
docker compose down -v     # supprime aussi les volumes (réinitialise tout)
```

## Configuration

Les secrets ne sont pas versionnés : `.env` est ignoré par git et
`.env.example` documente les variables. Compose refuse de démarrer si un mot de
passe manque.

| Variable | Obligatoire | Défaut | Rôle |
| --- | --- | --- | --- |
| `DB_PASSWORD` | oui | — | Utilisateur `matomo` de MariaDB |
| `DB_ROOT_PASSWORD` | oui | — | Root de la base Matomo |
| `WP_DB_PASSWORD` | oui | — | Utilisateur `wordpress` de MariaDB |
| `WP_DB_ROOT_PASSWORD` | oui | — | Root de la base WordPress |
| `TAG` | non | `1.0` | Tag des images construites |

Générer un mot de passe solide :

```bash
openssl rand -base64 24
```

Les images de base viennent du registre privé `sysadminmichael/sentinet`. Ce
sont des arguments de build, donc on peut les remplacer ponctuellement, par
exemple par les images officielles si le registre est inaccessible :

```bash
docker compose build --build-arg MARIADB_IMAGE=mariadb:lts
```

## Durcissement

Service `web` :

- `read_only: true`, avec des `tmpfs` pour `/var/cache/nginx`, `/var/run` et `/tmp`.
- `no-new-privileges:true` interdit l'escalade de privilèges.
- Healthcheck sur `/healthz`.

Configuration nginx (`nginx/default.conf`) : `server_tokens off`,
`X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`,
et une Content-Security-Policy limitée à Google Fonts et à `matomo.localhost`.

Proxy (`proxy/proxy.conf`) : toute requête avec un nom de domaine inconnu est
coupée (code 444). Les noms des conteneurs sont résolus à chaque requête, donc le
proxy démarre même si un service n'est pas encore prêt.
