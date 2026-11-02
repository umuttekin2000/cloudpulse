#syntax=docker/dockerfile:1
#─────────────────────────────────────────────────────────────────────────────
#CloudPulse: multi-stage build
#assets : Generates React/Vite output using Node (not included in final image)
#vendor : Installs Composer dependencies             (not included in final image)
#app    : PHP-FPM + application code                 -> web Pod, worker Pod, migrate Job
#web    : Nginx + static files                       -> second container of the web Pod
#Usage (from repo root):
#docker build --target app -t cloudpulse-app .
#docker build --target web -t cloudpulse-web .
#There are NO PASSWORDS, KEYS, or .env files inside the image. All configuration comes at runtime
#as environment variables (Kubernetes ConfigMap / Secret).
#─────────────────────────────────────────────────────────────────────────────

ARG PHP_VERSION=8.4
ARG NODE_VERSION=22
ARG NGINX_TAG=stable-alpine
ARG COMPOSER_VERSION=2

# ── 1) Frontend (Node) ─────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS assets
WORKDIR /build

COPY src/package.json src/package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

COPY src/vite.config.js ./
COPY src/resources ./resources
RUN npm run build


# ── 2) Composer Binary  ────────────────────────────────────────────────────
FROM composer:${COMPOSER_VERSION} AS composer-bin


# ── 3) PHP Base ───────────────────
FROM php:${PHP_VERSION}-fpm-alpine AS php-base

# hadolint ignore=DL3018,SC2086
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql pcntl opcache \
    && apk del --no-network .build-deps

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Defaults. Overridden with ConfigMap in Kubernetes.(docker/php.ini docker/php-fpm.conf ).

ENV PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_MAX_FILESIZE=12M \
    PHP_POST_MAX_SIZE=16M \
    PHP_FPM_MAX_CHILDREN=10


# ── 4) Composer Dependencies ───────────────────────────────────────────────
FROM php-base AS vendor
COPY --from=composer-bin /usr/bin/composer /usr/bin/composer

# hadolint ignore=DL3018
RUN apk add --no-cache unzip

WORKDIR /app
COPY src/composer.json src/composer.lock* ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction --no-progress

COPY src/ ./
RUN composer dump-autoload --no-dev --optimize --classmap-authoritative --no-interaction


# ── 5) TARGET "app": PHP-FPM + Laravel ────────────────────────────────────────
FROM php-base AS app

# CI/CD provides these two values at build time; they are displayed on the dashboard.
ARG APP_VERSION=dev
ARG APP_COMMIT_SHA=local
ENV APP_VERSION=${APP_VERSION} \
    APP_COMMIT_SHA=${APP_COMMIT_SHA}

COPY docker/php.ini /usr/local/etc/php/conf.d/zz-cloudpulse.ini
COPY docker/php-fpm.conf /usr/local/etc/php-fpm.d/zz-cloudpulse.conf
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
# If the file is saved with CRLF line endings on Windows, the script won't work; stay safe.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html
COPY --from=vendor --chown=www-data:www-data /app ./
COPY --from=assets --chown=www-data:www-data /build/public/build ./public/build

RUN mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R ug+rwX storage bootstrap/cache

EXPOSE 9000
ENTRYPOINT ["entrypoint.sh"]
CMD ["php-fpm"]


# ── 6) TARGET "web": Nginx (non-root, 8080) ─────────────────────
FROM nginxinc/nginx-unprivileged:${NGINX_TAG} AS web

# Defaults. Overridden with ConfigMap in Kubernetes.
ENV NGINX_CLIENT_MAX_BODY_SIZE=16m \
    PHP_FPM_ADDRESS=127.0.0.1:9000

# *.template files are rendered at startup with envsubst.
COPY docker/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=app /var/www/html/public /var/www/html/public

EXPOSE 8080
