# SentiNet — Stack Docker

Conteneurisation du projet **NetSentinel**, un outil de détection réseau assistée
par machine learning (projet YDays — Ynov Campus Toulouse). Le dossier s'appelle
`SentiNet`, le produit *NetSentinel* : c'est le même projet.

## Arborescence

```text
SentiNet/
├── dockerfile                 # Dockerfile multi-stage : une cible par service
├── docker-compose.yaml        # Orchestration des 6 services
├── .env.example               # Modèle des variables (à copier en .env)
├── .dockerignore              # Exclut .env, .git, compose et README du contexte de build
├── .gitignore                 # Ignore .env
├── config/mariadb/matomo.cnf  # Réglages MariaDB de Matomo (max_allowed_packet)
├── nginx/default.conf         # Configuration nginx du site vitrine
├── proxy/proxy.conf           # Configuration du reverse proxy
└── site/index.html            # Site vitrine (avec traceur Matomo)
```

## Services

Toutes les images sont construites depuis l'unique `dockerfile` multi-stage.
Seul le reverse proxy expose un port sur l'hôte.

| Service | Image construite | Image de base | URL | Rôle |
| --- | --- | --- | --- | --- |
| `nginx-proxy` | `sysadminmichael/sentinet-proxy` | `sysadminmichael/sentinet:nginx-1.27-alpine-slim` | port 80 | Reverse proxy par nom de domaine |
| `web` | `sysadminmichael/sentinet-web` | `sysadminmichael/sentinet:nginx-1.27-alpine-slim` | <http://netsentinel.localhost> | Site vitrine statique |
| `app` | `sysadminmichael/sentinet-matomo` | `sysadminmichael/sentinet:matomo-5-apache` | <http://matomo.localhost> | Analytics auto-hébergé |
| `db` | `sysadminmichael/sentinet-matomo-db` | `sysadminmichael/sentinet:db-12.3.3` | interne | Base de Matomo |
| `wordpress` | `sysadminmichael/sentinet-wordpress` | `wordpress:6-apache` | <http://wp.localhost> | WordPress |
| `wp-db` | `sysadminmichael/sentinet-wp-db` | `sysadminmichael/sentinet:db-12.3.3` | interne | Base de WordPress |

Chaque image construite est taguée avec `${TAG}` (par défaut `1.0`).

Réseaux :

- `front` relie le proxy au site, à Matomo et à WordPress.
- `back` est interne (pas d'accès Internet) et relie les applications à leurs bases.

`app` et `wordpress` attendent que leur base soit *healthy* avant de démarrer.
Tous les services redémarrent automatiquement (`restart: unless-stopped`).

Volumes persistants : `db`, `matomo`, `wp-db` et `wp-data`.

## Le dockerfile multi-stage

Toute la configuration non secrète est intégrée aux images. Le compose ne
transmet plus que les mots de passe, lus depuis `.env`.

| Cible | Base | Contenu ajouté |
| --- | --- | --- |
| `mariadb-base` | `MARIADB_IMAGE` | Healthcheck MariaDB commun aux deux bases |
| `db` | `mariadb-base` | `matomo.cnf`, base et utilisateur `matomo`, options d'upgrade auto |
| `app` | `MATOMO_IMAGE` | Connexion à `db`, préfixe de tables `matomo_` |
| `wp-db` | `mariadb-base` | Base et utilisateur `wordpress` |
| `wordpress` | `WORDPRESS_IMAGE` | Connexion à `wp-db` |
| `web` | `NGINX_IMAGE` | `nginx/default.conf`, le site, healthcheck `/healthz`, label `project=netsentinel` |
| `proxy` | `NGINX_IMAGE` | `proxy/proxy.conf` |

Construire une seule cible à la main :

```bash
docker build --target web -t sysadminmichael/sentinet-web:1.0 .
```

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

Publier les images construites sur le registre :

```bash
docker compose push
```

Arrêter la stack :

```bash
docker compose down        # conserve les données
docker compose down -v     # supprime aussi les volumes (réinitialise tout)
```

## Configuration

Les secrets ne sont pas versionnés : `.env` est ignoré par git, exclu du
contexte de build par `.dockerignore`, et `.env.example` documente les
variables. Compose refuse de démarrer si un mot de passe manque.

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

Les images de base sont des arguments de build (`NGINX_IMAGE`, `MATOMO_IMAGE`,
`MARIADB_IMAGE`, `WORDPRESS_IMAGE`). On peut donc les remplacer ponctuellement,
par exemple par les images officielles si le registre privé est inaccessible :

```bash
docker compose build \
  --build-arg MARIADB_IMAGE=mariadb:lts \
  --build-arg MATOMO_IMAGE=matomo:5-apache \
  --build-arg NGINX_IMAGE=nginx:1.27-alpine
```

## Durcissement

Service `web` :

- `read_only: true`, avec des `tmpfs` pour `/var/cache/nginx`, `/var/run` et `/tmp`.
- `no-new-privileges:true` interdit l'escalade de privilèges.
- Healthcheck sur `/healthz`.
- Le site et sa configuration sont copiés dans l'image, plus aucun bind mount.

Configuration nginx (`nginx/default.conf`) : `server_tokens off`,
`X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`,
et une Content-Security-Policy limitée à Google Fonts et à `matomo.localhost`.
La compression gzip est active et les fichiers statiques sont mis en cache 7 jours.

Proxy (`proxy/proxy.conf`) :

- Toute requête avec un nom de domaine inconnu est coupée (code 444).
- Les noms des conteneurs sont résolus à chaque requête par le DNS interne de
  Docker, donc le proxy démarre même si un service n'est pas encore prêt.
- Les en-têtes `Host`, `X-Real-IP`, `X-Forwarded-For` et `X-Forwarded-Proto`
  sont transmis aux applications.
- Les envois vers WordPress sont acceptés jusqu'à 64 Mo.

Bases de données : elles ne sont joignables que sur le réseau interne `back`.

## Historique des modifications

Par rapport à la première version de la stack :

- **Dockerfile multi-stage.** Le dockerfile ne construisait que le site. Il
  produit maintenant une image par service, avec une étape `mariadb-base` partagée.
- **Configuration déplacée dans les images.** Les variables non secrètes, les
  healthchecks et le label `project=netsentinel` sont passés du compose au dockerfile.
- **Fichier `matomo.cnf`.** Il remplace l'option `command: --max-allowed-packet=64MB`
  de la base Matomo.
- **Site intégré à l'image.** Les bind mounts de `site/` et `nginx/default.conf`
  ont été supprimés au profit d'un `COPY`.
- **Registre privé.** Les images de base viennent de `sysadminmichael/sentinet`
  et les images construites sont nommées `sysadminmichael/sentinet-*:${TAG}`.
- **Reverse proxy.** Un service `nginx-proxy` route par nom de domaine. Les
  ports 8080, 8081 et 8082 ne sont plus exposés, seul le port 80 l'est.
- **Réseaux séparés.** Le réseau `front` sert le proxy, le réseau interne
  `back` isole les bases de données.
- **Secrets.** Le fichier `.env` a été retiré du dépôt et ajouté au
  `.gitignore` et au `.dockerignore`. Compose exige désormais chaque mot de passe.
- **Traceur Matomo.** Le site et la CSP pointent vers `matomo.localhost` au
  lieu de `localhost:8081`.
- **Capabilities.** Les options `cap_drop` et `cap_add` du service `web` ont
  été retirées.
