#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 /path/to/site.env project-name"
    exit 1
fi

ENV_FILE="$1"
PROJECT_NAME="$2"

if [ ! -f "$ENV_FILE" ]; then
    echo "Env file not found: $ENV_FILE"
    exit 1
fi

set -a
. "$ENV_FILE"
set +a

required_vars="
SITE_DOMAIN
WORDPRESS_SITE_TITLE
WORDPRESS_ADMIN_USER
WORDPRESS_ADMIN_PASSWORD
WORDPRESS_ADMIN_EMAIL
"

for var in $required_vars; do
    eval "value=\${$var:-}"
    if [ -z "$value" ]; then
        echo "Missing required variable in $ENV_FILE: $var"
        exit 1
    fi
done

compose() {
    docker compose --env-file "$ENV_FILE" -p "$PROJECT_NAME" "$@"
}

echo "Bringing stack up for project: $PROJECT_NAME"
compose up -d --build

echo "Waiting for WordPress container to be ready..."
sleep 5

echo "Checking whether WordPress is already installed..."
if compose run --rm --no-deps wp-cli core is-installed >/dev/null 2>&1; then
    echo "WordPress is already installed for project: $PROJECT_NAME"
    exit 0
fi

echo "Installing WordPress for https://$SITE_DOMAIN ..."
compose run --rm --no-deps wp-cli core install \
    --url="https://$SITE_DOMAIN" \
    --title="$WORDPRESS_SITE_TITLE" \
    --admin_user="$WORDPRESS_ADMIN_USER" \
    --admin_password="$WORDPRESS_ADMIN_PASSWORD" \
    --admin_email="$WORDPRESS_ADMIN_EMAIL" \
    --skip-email

echo "Flushing rewrite rules..."
compose run --rm --no-deps wp-cli rewrite flush --hard

echo "Installation complete."
echo "Site: https://$SITE_DOMAIN"
echo "Admin user: $WORDPRESS_ADMIN_USER"
