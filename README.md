# NinerLog — Self-Hosted Deployment

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Images: GHCR](https://img.shields.io/badge/images-ghcr.io-2496ED)](https://github.com/fjaeckel?tab=packages&repo_name=ninerlog-dockerized)

Run your own instance of [NinerLog](https://ninerlog.com), the EASA/FAA compliant pilot logbook.

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/fjaeckel/ninerlog-dockerized.git
cd ninerlog-dockerized

# 2. Configure environment
cp .env.example .env
# Edit .env — at minimum set JWT_SECRET, REFRESH_SECRET, POSTGRES_PASSWORD

# 3. Start everything
docker compose up -d

# 4. Open NinerLog
# Visit http://localhost in your browser
```

The stack pulls pre-built, publicly available images from GitHub Container Registry — no login and no build step needed.

## What's Included

| Service | Image | Port |
|---------|-------|------|
| **API** | `ghcr.io/fjaeckel/ninerlog-api:latest` | 3000 (internal) |
| **Frontend** | `ghcr.io/fjaeckel/ninerlog-frontend:latest` | 80 / 443 |
| **PostgreSQL** | Custom (Alpine + auto-TLS) | 5432 (internal) |
| **Certbot** | `certbot/certbot:latest` | — |
| **DB Backup** | Custom (Alpine + pg_dump) | — |

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│   Browser   │────▶│  Frontend   │────▶│   API        │
│             │     │  (nginx)    │     │  (Go)        │
└─────────────┘     │  :80/:443   │     │  :3000       │
                    └─────────────┘     └──────┬───────┘
                                               │
                                        ┌──────▼───────┐
                                        │  PostgreSQL  │
                                        │  :5432 (TLS) │
                                        └──────────────┘
```

- **Frontend** serves the React PWA and reverse-proxies `/api/*` to the API container.
- **PostgreSQL** uses auto-generated self-signed TLS certificates for wire encryption between containers.
- **Certbot** handles Let's Encrypt certificate renewal for HTTPS.
- **DB Backup** runs scheduled `pg_dump` snapshots, gzip-compressed, with automatic retention pruning.

## Configuration

All configuration is done via environment variables in `.env`. See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for the full reference.

### Minimum Required

| Variable | Description |
|----------|-------------|
| `POSTGRES_PASSWORD` | Database password |
| `JWT_SECRET` | Secret key for access tokens (min. 32 chars) |
| `REFRESH_SECRET` | Secret key for refresh tokens (min. 32 chars) |

That's it for local, HTTP-only testing — `TLS_DOMAIN` is left empty and `CORS_ORIGIN` defaults to `http://localhost` in `.env.example`, so `docker compose up -d` serves plain HTTP on port 80 without any domain or certificate setup.

### For Production (HTTPS)

| Variable | Description |
|----------|-------------|
| `TLS_DOMAIN` | Your domain name (e.g. `logbook.example.com`) |
| `CORS_ORIGIN` | Must match your domain (e.g. `https://logbook.example.com`) |
| `VITE_API_BASE_URL` | Usually `/api/v1` (default) |

See [docs/HTTPS.md](docs/HTTPS.md) for the full TLS/Let's Encrypt setup.

## Updating

```bash
# Pull latest images
docker compose pull

# Restart with new images
docker compose up -d
```

See [docs/UPGRADING.md](docs/UPGRADING.md) for version pinning and migration notes.

## Documentation

- [Configuration Reference](docs/CONFIGURATION.md) — All environment variables
- [HTTPS Setup](docs/HTTPS.md) — Let's Encrypt / TLS configuration
- [Passkeys / WebAuthn](docs/PASSKEYS.md) — Enabling passwordless sign-in
- [Upgrading](docs/UPGRADING.md) — Pulling new versions, migrations
- [Backups](docs/BACKUPS.md) — Automated database backups and restore
- [Cloud Backups](docs/CLOUD_BACKUPS.md) — Per-user encrypted backups to pluggable cloud storage providers
- [Monitoring](docs/MONITORING.md) — Private Prometheus scraping of the `/metrics` endpoint
- [API Documentation](https://github.com/fjaeckel/ninerlog-api/blob/main/api-spec/openapi.yaml) — OpenAPI 3.1 specification

## License

This repository (deployment tooling) is [MIT licensed](LICENSE). The application code has its own licenses:
- [ninerlog-api](https://github.com/fjaeckel/ninerlog-api) — AGPL-3.0
- [ninerlog-frontend](https://github.com/fjaeckel/ninerlog-frontend) — MIT
