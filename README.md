# NinerLog — Free, Open-Source Pilot Logbook for EASA & FAA Pilots

**A modern digital pilot logbook you can actually own.** Log flights in seconds, track EASA and FAA currency automatically, get training flights signed by your instructor, and export everything whenever you want. Use the free hosted version at [app.ninerlog.com](https://app.ninerlog.com), or self-host the whole stack with one `docker compose up`.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![API: AGPL-3.0](https://img.shields.io/badge/API-AGPL--3.0-orange.svg)](https://github.com/fjaeckel/ninerlog-api)
[![Images: GHCR](https://img.shields.io/badge/images-ghcr.io-2496ED)](https://github.com/fjaeckel?tab=packages&repo_name=ninerlog)
[![Website](https://img.shields.io/badge/website-ninerlog.com-0EA5E9)](https://ninerlog.com)
[![Self-hosted: Docker Compose](https://img.shields.io/badge/self--hosted-Docker%20Compose-2496ED)](https://ninerlog.com/self-hosted)

[**Website**](https://ninerlog.com) · [**Launch the app**](https://app.ninerlog.com) · [**Self-hosting guide**](https://ninerlog.com/self-hosted) · [**Features**](https://ninerlog.com/features)

---

![NinerLog pilot logbook — flight logging](https://ninerlog.com/images/feature-flight-logging.png)

## Quick Start (Docker Compose)

```bash
# 1. Clone this repo
git clone https://github.com/fjaeckel/ninerlog.git
cd ninerlog

# 2. Configure environment
cp .env.example .env
# Edit .env — at minimum set JWT_SECRET, REFRESH_SECRET, POSTGRES_PASSWORD

# 3. Start everything
docker compose up -d

# 4. Open NinerLog
# Visit http://localhost in your browser
```

The stack pulls pre-built, publicly available images from GitHub Container Registry — no login, no build step, no toolchain to install. For HTTPS with a real domain, see [docs/HTTPS.md](docs/HTTPS.md).

## Screenshots

| Quick Log — live block times | Currency tracking |
|---|---|
| ![Quick Log with live block times](https://ninerlog.com/images/feature-quick-log.png) | ![EASA and FAA currency tracking](https://ninerlog.com/images/feature-currency-tracking.png) |

| Instructor signing | Flight search |
|---|---|
| ![Digital instructor signature on training flights](https://ninerlog.com/images/feature-instructor-signing.png) | ![Search across registration, type, airports and remarks](https://ninerlog.com/images/feature-search.png) |

| Reports & statistics | Flying club admin |
|---|---|
| ![Flight hours reports and route maps](https://ninerlog.com/images/feature-reports.png) | ![Built-in admin panel for flying clubs](https://ninerlog.com/images/feature-flying-club.png) |

## Features

**Flight logging**
- Quick entry templates — logging a flight is a 30-second habit
- Block times, flight times, and advanced time splits
- Day and night landings tracked separately
- IFR approaches, holds, and instrument time
- **Quick Log** — tap once at off-block, takeoff, landing, and on-block; the entry writes itself, with GPS airport detection and offline support

**Licenses & currency**
- Multi-license support — hold a PPL and an SPL, EASA and FAA, all at once
- Flights count toward every applicable license and class rating automatically
- Class ratings with expiry tracking (SEP, MEP, TMG, IR)
- EASA revalidation rules (FCL.740) and FAA 90-day passenger currency (14 CFR 61.57)
- Instrument currency with approach counting

**Training**
- Instructor signs on your phone after the debrief, or remotely via a secure link or QR code
- Signing links expire on your terms (24 hours to 30 days)
- Signed entries lock against edits; voiding leaves a documented audit trail

**Your data**
- Import from CSV and XLS with automatic field mapping
- Export to CSV, PDF, and JSON, including EASA-compliant logbook PDF
- Optional scheduled backups to any S3-compatible bucket **you** own
- No vendor lock-in — ever

**Search & reports**
- One search box across registration, type, departure/arrival ICAO, and remarks
- Stack date range, aircraft, airport, and pilot-function filters on top
- Flight hours by aircraft type, period, and license; route maps and airport heatmaps

**Security**
- Passkey sign-in (Face ID, Touch ID, Windows Hello, hardware keys)
- TOTP two-factor authentication with any standard authenticator app
- Printable one-time recovery codes

**Self-hosted extras**
- Built-in admin panel — invite, enable, disable, and reset members without touching the database
- Club-wide announcements pushed to members' dashboards
- Every pilot keeps their own private logbook on your server

**Everywhere**
- Fully responsive — phone, tablet, desktop; no app install required
- English and German, with more languages coming

## What's Included

| Service | Image | Port |
|---------|-------|------|
| **API** | `ghcr.io/fjaeckel/ninerlog-api:latest` | 3000 (internal) |
| **Frontend** | `ghcr.io/fjaeckel/ninerlog-frontend:latest` | 80 / 443 |
| **PostgreSQL** | Custom (Alpine + auto-TLS) | 5432 (internal) |
| **Certbot** | `certbot/certbot:latest` | — |
| **DB Backup** | Custom (Alpine + pg_dump) | — |

### Architecture

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

## Repositories

| Repository | Purpose | License |
|------------|---------|---------|
| [ninerlog](https://github.com/fjaeckel/ninerlog) (this repo) | Self-hosted deployment — Docker Compose, docs | MIT |
| [ninerlog-api](https://github.com/fjaeckel/ninerlog-api) | Backend API (Go) | AGPL-3.0 |
| [ninerlog-frontend](https://github.com/fjaeckel/ninerlog-frontend) | Web app (React PWA) | MIT |

## License

This repository — the deployment tooling, Compose files, and documentation — is [MIT licensed](LICENSE).

The application itself is split across two repos with their own licenses: the [API](https://github.com/fjaeckel/ninerlog-api) is **AGPL-3.0**, and the [frontend](https://github.com/fjaeckel/ninerlog-frontend) is **MIT**. Running a self-hosted instance for yourself or your club is unrestricted; the AGPL obligations on the API apply if you offer a modified version of it over a network.
