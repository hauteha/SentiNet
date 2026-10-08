
ARG MARIADB_IMAGE=mariadb:lts
ARG MATOMO_IMAGE=matomo:5-apache
ARG WORDPRESS_IMAGE=wordpress:6-apache
ARG NGINX_IMAGE=nginx:1.27-alpine


FROM ${MARIADB_IMAGE} AS mariadb-base
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD ["healthcheck.sh", "--connect", "--innodb_initialized"]


FROM mariadb-base AS db
# Remplace "command: --max-allowed-packet=64MB"
COPY config/mariadb/matomo.cnf /etc/mysql/conf.d/matomo.cnf
ENV MARIADB_AUTO_UPGRADE=1 \
    MARIADB_DISABLE_UPGRADE_BACKUP=1 \
    MARIADB_INITDB_SKIP_TZINFO=1 \
    MARIADB_DATABASE=matomo \
    MARIADB_USER=matomo


FROM ${MATOMO_IMAGE} AS app
ENV MATOMO_DATABASE_ADAPTER=mysql \
    MATOMO_DATABASE_HOST=db \
    MATOMO_DATABASE_DBNAME=matomo \
    MATOMO_DATABASE_USERNAME=matomo \
    MATOMO_DATABASE_TABLES_PREFIX=matomo_


FROM mariadb-base AS wp-db
ENV MARIADB_DATABASE=wordpress \
    MARIADB_USER=wordpress


FROM ${WORDPRESS_IMAGE} AS wordpress
ENV WORDPRESS_DB_HOST=wp-db \
    WORDPRESS_DB_NAME=wordpress \
    WORDPRESS_DB_USER=wordpress


FROM ${NGINX_IMAGE} AS web
RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY site/ /usr/share/nginx/html/
LABEL project=netsentinel
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1