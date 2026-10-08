# Docker — M2 Infrastructure

Travaux de conteneurisation du M2 Infrastructure. Ce dépôt regroupe les stacks
Docker du projet **NetSentinel**, un outil de détection réseau assistée par
machine learning (projet YDays — Ynov Campus Toulouse).

## Contenu

| Chemin | Rôle |
| --- | --- |
| `SentiNet/` | Stack du site vitrine NetSentinel + instance Matomo d'analytics |
| `SentiNet/dockerfile` | Image nginx autonome avec le site embarqué |
| `SentiNet/docker-compose.yaml` | Orchestration des 3 services (site, Matomo, MariaDB) |
| `SentiNet/nginx/default.conf` | Configuration nginx durcie (CSP, en-têtes de sécurité, gzip, cache) |
| `SentiNet/site/index.html` | Page vitrine statique (autonome, sans build) |

## Stack SentiNet

Trois services définis dans `docker-compose.yaml` :

| Service | Image | Port hôte | Rôle |
| --- | --- | --- | --- |
| `web` | `nginx:1.27-alpine` | `${HTTP_PORT:-8080}` | Sert le site vitrine statique |
| `app` | `matomo:5-apache` | `${MATOMO_PORT:-8081}` | Analytics auto-hébergé |
| `db` | `mariadb:lts` | — (interne) | Base de données de Matomo |

Le démarrage est ordonné : `app` attend que `db` soit déclaré *healthy*
(`depends_on` + `condition: service_healthy`), et non simplement démarré.

## Démarrage

Prérequis : Docker Desktop (ou Docker Engine) avec le plugin Compose.

```bash
cd SentiNet
cp .env.example .env     # puis renseigner des mots de passe forts
docker compose up -d
```

- Site vitrine → <http://localhost:8080>
- Matomo (installation guidée au 1er lancement) → <http://localhost:8081>

Vérifier l'état des services et la sonde de santé :

```bash
docker compose ps
curl http://localhost:8080/healthz    # doit répondre "ok"
```

Arrêter la stack (`-v` supprime aussi les volumes de données) :

```bash
docker compose down        # conserve les données
docker compose down -v     # réinitialise tout
```

## Image autonome

`dockerfile` produit une image nginx avec le site **copié dedans** — utile pour
un déploiement où aucun volume n'est monté :

```bash
cd SentiNet
docker build -f dockerfile -t netsentinel-site:v1 .
docker run --rm -p 8080:80 netsentinel-site:v1
```

À noter : le service `web` du Compose n'utilise pas cette image. Il monte
`./site` et `./nginx/default.conf` en lecture seule depuis l'hôte, ce qui permet
de modifier la page sans reconstruire. Les deux approches coexistent
volontairement — bind mount pour le développement, image buildée pour la
production.

## Durcissement appliqué

Le service `web` ne tourne pas avec les réglages par défaut :

- `read_only: true` — système de fichiers du conteneur en lecture seule, avec
  des `tmpfs` sur `/var/cache/nginx`, `/var/run` et `/tmp` pour les écritures
  dont nginx a réellement besoin
- `cap_drop: ALL` puis réintroduction des seules capacités nécessaires
  (`CHOWN`, `SETGID`, `SETUID`, `NET_BIND_SERVICE`)
- `no-new-privileges:true` — interdit l'escalade de privilèges
- Montages en `:ro` pour le site et la configuration

Côté nginx (`nginx/default.conf`) : `server_tokens off`, `X-Frame-Options:
DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy` et une
Content-Security-Policy restreinte aux seules origines Google Fonts utilisées
par la page.

## Configuration

Les secrets ne sont pas versionnés. `SentiNet/.env.example` documente les
variables attendues ; `.env` est ignoré par git.

| Variable | Obligatoire | Défaut | Rôle |
| --- | --- | --- | --- |
| `DB_PASSWORD` | oui | — | Mot de passe de l'utilisateur `matomo` |
| `DB_ROOT_PASSWORD` | oui | — | Mot de passe root de MariaDB |
| `HTTP_PORT` | non | `8080` | Port hôte du site vitrine |
| `MATOMO_PORT` | non | `8081` | Port hôte de Matomo |

Générer un mot de passe solide :

```bash
openssl rand -base64 32
```

## Notes

Le dossier s'appelle `SentiNet` tandis que le produit est nommé *NetSentinel*
dans la page web. Les deux désignent le même projet.
