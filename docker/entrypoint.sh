#!/bin/sh
set -eu

if [ "${SKIP_LARAVEL_CACHE:-0}" != "1" ]; then
    php artisan config:cache --no-interaction
    php artisan route:cache --no-interaction
    php artisan view:cache --no-interaction
fi

exec "$@"
