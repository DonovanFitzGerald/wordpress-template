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

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required"
    exit 1
fi

if ! command -v doctl >/dev/null 2>&1; then
    echo "doctl is required"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required"
    exit 1
fi

set -a
. "$ENV_FILE"
set +a

required_vars="
SITE_DOMAIN
SITE_HOSTNAME
WORDPRESS_DB_HOST
WORDPRESS_DB_NAME
WORDPRESS_DB_USER
DB_CLUSTER_ID
DB_AUTH_TOKEN
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

random_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48 | tr -d '\n'
    else
        head -c 48 /dev/urandom | base64 | tr -d '\n'
    fi
}

ensure_env_var() {
    key="$1"
    file="$2"

    current_value="$(grep "^${key}=" "$file" 2>/dev/null | head -n 1 | cut -d '=' -f 2- || true)"

    if [ -z "$current_value" ] || [ "$current_value" = "put-a-long-random-string-here" ]; then
        new_value="$(random_secret)"
        upsert_env_var "$key" "$new_value" "$file"
        echo "Generated $key"
    fi
}

compose() {
    docker compose --env-file "$ENV_FILE" -p "$PROJECT_NAME" "$@"
}

upsert_env_var() {
    key="$1"
    value="$2"
    file="$3"

    escaped_key=$(printf '%s' "$key" | sed 's/[][\/.^$*]/\\&/g')
    escaped_value=$(printf '%s' "$value" | sed 's/[\/&]/\\&/g')

    if grep -q "^${escaped_key}=" "$file"; then
        sed -i "s/^${escaped_key}=.*/${key}=${escaped_value}/" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

DB_NAME="${WORDPRESS_DB_NAME}"
DB_USER="${WORDPRESS_DB_USER}"
CLUSTER_ID="${DB_CLUSTER_ID}"

export DIGITALOCEAN_ACCESS_TOKEN="${DB_AUTH_TOKEN}"

echo "Checking DigitalOcean managed database: $CLUSTER_ID"

echo "Ensuring database exists: $DB_NAME"
if ! doctl databases db list "$CLUSTER_ID" --format Name --no-header | grep -Fxq "$DB_NAME"; then
    doctl databases db create "$CLUSTER_ID" "$DB_NAME"
else
    echo "Database already exists: $DB_NAME"
fi

USER_CREATED=0

echo "Ensuring database user exists: $DB_USER"
if ! doctl databases user list "$CLUSTER_ID" --format Name --no-header | grep -Fxq "$DB_USER"; then
    doctl databases user create "$CLUSTER_ID" "$DB_USER" >/dev/null
    USER_CREATED=1
    echo "Created database user: $DB_USER"
else
    echo "Database user already exists: $DB_USER"
fi

DB_PASS=""

if [ "$USER_CREATED" -eq 1 ]; then
    echo "Fetching generated password for newly created user"
    USER_JSON="$(doctl databases user get "$CLUSTER_ID" "$DB_USER" -o json)"
    DB_PASS="$(printf '%s' "$USER_JSON" | jq -r '.[0].password // empty')"
fi

if [ -z "$DB_PASS" ]; then
    if [ -n "${WORDPRESS_DB_PASSWORD:-}" ]; then
        echo "Using existing WORDPRESS_DB_PASSWORD from env file"
        DB_PASS="$WORDPRESS_DB_PASSWORD"
    else
        echo "No password available for $DB_USER"
        echo "The user already existed, and DigitalOcean does not return its current password."
        echo "Reset the DB user password, then rerun this script."
        echo ""
        echo "Example:"
        echo "  doctl databases user reset $CLUSTER_ID $DB_USER"
        exit 1
    fi
fi

echo "Updating env file with database password"
upsert_env_var "WORDPRESS_DB_PASSWORD" "$DB_PASS" "$ENV_FILE"

ensure_env_var "WORDPRESS_AUTH_KEY" "$ENV_FILE"
ensure_env_var "WORDPRESS_SECURE_AUTH_KEY" "$ENV_FILE"
ensure_env_var "WORDPRESS_LOGGED_IN_KEY" "$ENV_FILE"
ensure_env_var "WORDPRESS_NONCE_KEY" "$ENV_FILE"
ensure_env_var "WORDPRESS_AUTH_SALT" "$ENV_FILE"
ensure_env_var "WORDPRESS_SECURE_AUTH_SALT" "$ENV_FILE"
ensure_env_var "WORDPRESS_LOGGED_IN_SALT" "$ENV_FILE"
ensure_env_var "WORDPRESS_NONCE_SALT" "$ENV_FILE"

set -a
. "$ENV_FILE"
set +a

echo "Bringing stack up for project: $PROJECT_NAME"
compose up -d --build

echo "Waiting for WordPress container to be ready..."
sleep 8

echo "Checking whether WordPress is already installed..."
if ! compose run --rm --no-deps wp-cli core is-installed >/dev/null 2>&1; then
    echo "Installing WordPress for https://$SITE_DOMAIN ..."
    compose run --rm --no-deps wp-cli core install \
        --url="https://$SITE_DOMAIN" \
        --title="${WORDPRESS_SITE_TITLE:-$SITE_HOSTNAME}" \
        --admin_user="$WORDPRESS_ADMIN_USER" \
        --admin_password="$WORDPRESS_ADMIN_PASSWORD" \
        --admin_email="$WORDPRESS_ADMIN_EMAIL" \
        --skip-email

    echo "Flushing rewrite rules..."
    compose run --rm --no-deps wp-cli rewrite flush --hard
else
    echo "WordPress is already installed for project: $PROJECT_NAME"
fi

if [ -n "${WP_MIGRATE_ZIP:-}" ] && [ -f "$WP_MIGRATE_ZIP" ]; then
    echo "Installing or activating WP Migrate..."
    compose run --rm --no-deps wp-cli plugin install "$WP_MIGRATE_ZIP" --force --activate
fi

echo "Installation complete."
echo "Site: https://$SITE_DOMAIN"
echo "Admin user: $WORDPRESS_ADMIN_USER"
