# wordpress-template

Reusable Docker-based WordPress site template for deploying multiple isolated WordPress sites behind a shared Traefik reverse proxy.

This template is designed for a hosting setup where:

- Traefik is managed in a separate infrastructure repo
- Redis is shared across sites
- MySQL is external
- each WordPress site gets its own containers, volume, database, and env file
- site creation and maintenance are done through Docker Compose and WP-CLI

---

## Features

- Nginx + WordPress PHP-FPM split
- external MySQL support
- shared Redis support
- Traefik label-based routing
- per-site named Docker volume
- WP-CLI support
- bootstrap/install scripts
- custom WordPress config support
- reusable per-site env-driven deployment model

---

## Repo Structure

```text
wordpress-site-template/
├── compose.yaml
├── .env.example
├── README.md
├── /php
│   ├── Dockerfile
│   ├── php.ini
│   └── entrypoint.sh
├── /nginx
│   └── site.conf.template
├── /scripts
│   ├── bootstrap-site.sh
│   ├── wp-install.sh
│   └── wp-cli.sh
├── /config
│   └── wp-config-extra.php
├── /data
│   └── .gitkeep
└── /docs
    └── usage.md
```

---

## How it works

Each site created from this template runs with:

- one `nginx` container
- one `wordpress` PHP-FPM container
- one optional `wp-cli` tooling container
- one one-shot `redis-check` container
- one named Docker volume for the WordPress filesystem

Traffic flow:

```text
Visitor
  -> DNS
  -> Traefik
  -> nginx
  -> wordpress (php-fpm)
  -> external MySQL
  -> shared Redis
```

This repo does not manage Traefik, Redis, or MySQL directly. It expects those to already exist.

---

## Requirements

Before using this template, you should already have:

- Docker
- Docker Compose
- a shared Traefik instance
- a shared external Docker `proxy` network
- a shared external Docker `redis` network
- a Redis container reachable on that network
- an external MySQL database and database user for each site
- DNS access for creating site records

---

## Recommended host layout

```text
/opt/
  hosting-platform/
  wordpress-template/
  wordpress-envs/
```

Suggested purpose:

- `/opt/hosting-platform` → shared infra repo
- `/opt/wordpress-template` → this repo
- `/opt/wordpress-envs` → one env file per site

---

## Site model

Each site should have:

- its own domain or subdomain
- its own env file
- its own database
- its own Redis prefix
- its own Docker volume
- its own Compose project name

Example:

- domain: `example.com`
- env file: `/opt/wordpress-envs/example.env`
- compose project: `example`

---

## Environment configuration

Copy `.env.example` and create one env file per site outside the repo.

Example:

```env
# Routing
SITE_DOMAIN=example.com
SITE_HOSTNAME=example

# Shared Docker networks
PROXY_NETWORK=proxy
REDIS_NETWORK=redis

# WordPress app
WORDPRESS_ENV=production
WORDPRESS_DEBUG=false
WORDPRESS_TABLE_PREFIX=wp_

# Database
WORDPRESS_DB_HOST=db.example-host.com:3306
WORDPRESS_DB_NAME=example
WORDPRESS_DB_USER=example_user
WORDPRESS_DB_PASSWORD=replace_with_strong_password

# Redis
WORDPRESS_REDIS_HOST=redis
WORDPRESS_REDIS_PORT=6379
WORDPRESS_REDIS_PREFIX=example:

# Security
WORDPRESS_AUTH_KEY=put-a-long-random-string-here
WORDPRESS_SECURE_AUTH_KEY=put-a-long-random-string-here
WORDPRESS_LOGGED_IN_KEY=put-a-long-random-string-here
WORDPRESS_NONCE_KEY=put-a-long-random-string-here
WORDPRESS_AUTH_SALT=put-a-long-random-string-here
WORDPRESS_SECURE_AUTH_SALT=put-a-long-random-string-here
WORDPRESS_LOGGED_IN_SALT=put-a-long-random-string-here
WORDPRESS_NONCE_SALT=put-a-long-random-string-here

# Email
SMTP_HOST=smtp.mailgun.org
SMTP_PORT=587
SMTP_USER=postmaster@example.com
SMTP_PASSWORD=replace_with_smtp_password
```

### Notes

- `SITE_DOMAIN` must be a hostname, not a path
- `SITE_HOSTNAME` is used in container names, router names, and volume names
- `WORDPRESS_DB_HOST` may include `host:port`
- each site should use a unique Redis prefix
- if an env value contains `$`, escape it as `$$`

---

## Installation

Clone the repo onto the VM:

```bash
cd /opt
git clone <your-repo-url> wordpress-template
cd wordpress-template
```

Create a site env file:

```bash
nano /opt/wordpress-envs/example.env
```

---

## Basic usage

### Bring up a site

```bash
docker compose --env-file /opt/wordpress-envs/example.env -p example up -d --build
```

### Stop a site

```bash
docker compose --env-file /opt/wordpress-envs/example.env -p example down
```

### Destroy a site and its volume

```bash
docker compose -p example down --volumes --remove-orphans --rmi local
```

Be careful: this removes the WordPress filesystem volume too.

---

## First-time WordPress install

Preferred method:

```bash
./scripts/wp-install.sh /opt/wordpress-envs/example.env example
```

This script should:

- bring the stack up
- check whether WordPress is already installed
- install WordPress if needed
- flush rewrite rules

If the site already exists, it should safely exit.

---

## WP-CLI usage

Run WP-CLI commands through the `wp-cli` container.

Example:

```bash
docker compose --env-file /opt/wordpress-envs/example.env -p example run --rm --no-deps wp-cli plugin list
```

More examples:

```bash
docker compose --env-file /opt/wordpress-envs/example.env -p example run --rm --no-deps wp-cli core is-installed

docker compose --env-file /opt/wordpress-envs/example.env -p example run --rm --no-deps wp-cli option get home

docker compose --env-file /opt/wordpress-envs/example.env -p example run --rm --no-deps wp-cli rewrite flush --hard
```

---

## DNS

Each site needs a DNS record pointing to the VM.

Typical setup:

- Type: `A`
- Name: `subdomain`
- Content: VM public IP

Example:

- `example.com`

Useful checks:

```bash
dig A example.com @1.1.1.1
dig AAAA example.com @1.1.1.1
curl -I http://example.com
curl -Ik https://example.com
```

Expected:

- HTTP returns a redirect to HTTPS
- HTTPS returns `200`

---

## Traefik expectations

This repo expects Traefik to be managed elsewhere.

The shared Traefik instance should:

- expose ports `80` and `443`
- watch Docker
- use the shared `proxy` network
- redirect HTTP to HTTPS globally

Each site is routed using labels on the `nginx` container.

---

## Persistence

The site filesystem is stored in a named Docker volume:

```text
${SITE_HOSTNAME}_wordpress_data
```

This stores:

- WordPress core
- themes
- plugins
- uploads
- generated files

This is useful for persistent runtime state, even if your main migration workflow is based on external backups or site transfer tools.

---

## Scripts

### `scripts/wp-install.sh`

Installs WordPress if not already installed.

Use when:

- creating a new blank site
- bootstrapping first-time setup

### `scripts/bootstrap-site.sh`

Intended for fuller site bootstrap workflows.

Typical use:

- bring the stack up
- validate setup
- run initial site provisioning steps

### `scripts/wp-cli.sh`

Convenience wrapper for WP-CLI commands.

Useful for:

- reducing repetitive long Compose commands
- plugin/theme operations
- admin and option management

---

## Custom PHP and WordPress config

### `php/Dockerfile`

Builds the custom WordPress PHP-FPM image.

Use this for:

- PHP extension installation
- custom PHP packages
- custom base image behavior

### `php/php.ini`

Use this to tune:

- memory limits
- upload size
- execution limits
- migration-related PHP settings

### `config/wp-config-extra.php`

Place custom WordPress constants and PHP-side runtime config here.

Typical use:

- environment-specific constants
- reverse proxy handling
- Redis constants
- security-related config

---

## Nginx config

### `nginx/site.conf.template`

This is the per-site Nginx config loaded into the `nginx` container.

It should:

- serve `/var/www/html`
- route PHP to the `wordpress` service
- support larger uploads if needed
- support longer FastCGI timeouts for migrations

---

## Common workflows

### Create a new blank site

1. Create DB and DB user
2. Create site env file
3. Create Cloudflare DNS record
4. Run:

```bash
./scripts/wp-install.sh /opt/wordpress-envs/site.env site-project
```

5. Verify:

```bash
curl -I http://site.example.com
curl -Ik https://site.example.com
```

### Check logs

```bash
docker compose --env-file /opt/wordpress-envs/site.env -p site-project logs --tail=100 nginx
docker compose --env-file /opt/wordpress-envs/site.env -p site-project logs --tail=100 wordpress
```

### Check container state

```bash
docker compose --env-file /opt/wordpress-envs/site.env -p site-project ps
```

### Rebuild after config changes

```bash
docker compose --env-file /opt/wordpress-envs/site.env -p site-project up -d --build
```

---

## Documentation

Additional operator documentation should live in:

```text
/docs/usage.md
```

This README should stay focused on structure, purpose, setup, and common usage.

---
