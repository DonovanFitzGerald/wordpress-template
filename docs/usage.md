# WordPress Docker Template Usage

## Overview

This repository is a reusable WordPress site template designed to run behind a shared Traefik reverse proxy on a VM.

Each site created from this template uses:

- Nginx for HTTP serving
- WordPress PHP-FPM for PHP execution
- an external MySQL database
- a shared Redis instance
- a Docker-managed named volume for persistent site files
- Traefik labels for per-site routing

This setup is intended for creating many small WordPress sites from the same template while keeping the hosting layer centralized.

---

## Architecture

### Traffic flow

```text
Visitor
  -> Cloudflare DNS / proxy
  -> Traefik (shared hosting repo)
  -> site nginx container
  -> wordpress php-fpm container
  -> external MySQL
  -> shared Redis
```
