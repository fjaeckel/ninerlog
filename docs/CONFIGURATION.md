# Configuration Reference

All NinerLog configuration is done via environment variables in the `.env` file.

## Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTGRES_PASSWORD` | PostgreSQL password | `my-secure-db-password` |
| `JWT_SECRET` | HMAC secret for access tokens (min 32 chars) | `openssl rand -hex 32` |
| `REFRESH_SECRET` | HMAC secret for refresh tokens (min 32 chars) | `openssl rand -hex 32` |

### Generating Secrets

```bash
# Generate random secrets
echo "JWT_SECRET=$(openssl rand -hex 32)" >> .env
echo "REFRESH_SECRET=$(openssl rand -hex 32)" >> .env
echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)" >> .env
```

## Database

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_DB` | `ninerlog` | Database name |
| `POSTGRES_USER` | `ninerlog` | Database user |
| `POSTGRES_PASSWORD` | — | Database password |

Data is persisted in a Docker volume (`postgres_data`). The database uses auto-generated self-signed TLS certificates for wire encryption between the API and Postgres containers.

## Authentication

| Variable | Default | Description |
|----------|---------|-------------|
| `JWT_SECRET` | — | HMAC signing key for access tokens |
| `REFRESH_SECRET` | — | HMAC signing key for refresh tokens |
| `JWT_EXPIRES_IN` | `15m` | Access token lifetime (Go duration) |
| `REFRESH_EXPIRES_IN` | `7d` | Refresh token lifetime (Go duration) |

## Networking

| Variable | Default | Description |
|----------|---------|-------------|
| `CORS_ORIGIN` | `http://localhost` | Allowed CORS origin (must match your domain) |
| `TLS_DOMAIN` | — | Domain for HTTPS / Let's Encrypt |
| `FRONTEND_PORT` | `80` | HTTP port on the host |
| `FRONTEND_TLS_PORT` | `443` | HTTPS port on the host |

## WebAuthn / Passkeys

Optional passwordless sign-in. Disabled when `WEBAUTHN_RP_ID` is empty.
See [PASSKEYS.md](PASSKEYS.md) for the full setup guide.

| Variable | Default | Description |
|----------|---------|-------------|
| `WEBAUTHN_RP_ID` | — | Relying-Party ID (registrable domain, e.g. `logbook.example.com`). Empty disables passkeys. |
| `WEBAUTHN_RP_NAME` | `NinerLog` | Human-readable name shown by the authenticator UI |
| `WEBAUTHN_RP_ORIGINS` | falls back to `CORS_ORIGIN` | Comma-separated list of full origins (scheme + host + port) |

## OIDC Single Sign-On

Optional delegation of all authentication to an external OpenID Connect provider
(Authentik, Keycloak, Authelia, Entra ID, Google, …). **Setting `OIDC_ISSUER` is a mode
switch** — password login, registration, TOTP and passkeys are disabled while it is set.
See [OIDC.md](OIDC.md) for the full setup and migration guide.

| Variable | Default | Description |
|----------|---------|-------------|
| `OIDC_ISSUER` | — | Provider issuer URL. **Setting it enables OIDC mode.** |
| `OIDC_CLIENT_ID` | — | Client ID from the provider |
| `OIDC_CLIENT_SECRET` | — | Client secret (confidential client) |
| `OIDC_REDIRECT_URL` | — | `https://<your-domain>/api/v1/auth/oidc/callback` — must match the provider registration exactly |
| `OIDC_POST_LOGIN_REDIRECT` | — | Frontend URL after login: `https://<your-domain>/auth/callback` |
| `OIDC_PROVIDER_NAME` | `Single sign-on` | Label on the sign-in button |
| `OIDC_SCOPES` | `openid profile email` | Extra scopes if the provider needs them for the email claim |
| `OIDC_NAME_CLAIM` | `name` | ID-token claim used as the display name |
| `OIDC_LINK_BY_VERIFIED_EMAIL` | `false` | Adopt existing local accounts by verified email on first OIDC login (migration only — see [OIDC.md](OIDC.md)) |
| `OIDC_TRUST_EMAIL_VERIFIED` | `false` | Treat addresses as verified when the provider omits `email_verified` |
| `OIDC_LOGIN_STATE_TTL` | `10m` | Window to complete a started login (Go duration) |
| `OIDC_HANDOFF_TTL` | `60s` | Lifetime of the one-time post-login handoff code |

## Server

| Variable | Default | Description |
|----------|---------|-------------|
| `GIN_MODE` | `release` | Gin framework mode: `debug`, `release`, `test` |
| `LOG_LEVEL` | `info` | Log verbosity: `debug`, `info`, `warn`, `error` |

## Rate Limiting

Every `/api/v1` route is limited to 120 requests/minute per user, with tighter
budgets on specific endpoints. Only the flight-search budget is tunable — the
rest are fixed in the API.

| Variable | Default | Description |
|----------|---------|-------------|
| `SEARCH_RATE_LIMIT_PER_MINUTE` | `60` | Flight searches (`GET /flights?q=`) allowed per minute per user. Search is interactive — the UI issues a request per debounced keystroke and re-runs on every filter, sort, and page change — so this needs far more headroom than a one-shot export. Unparseable or non-positive values are ignored with a warning |
| `DISABLE_RATE_LIMIT` | unset | Set to `true` to disable **all** rate limiting. For local development only — do not set this on an internet-facing deployment |

Users being throttled shows up as HTTP 429s. If you run the Prometheus/Grafana
stack, import the **NinerLog API — Rate Limits** dashboard from the API repo and
watch the per-limiter rejection ratio before changing these; see
[MONITORING.md](./MONITORING.md).

## App

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_API_BASE_URL` | `/api/v1` | API base URL as seen by the browser |
| `VITE_ENV` | `production` | Environment label |
| `APP_NAME` | — | Custom application name |
| `BETA_PASSWORD` | — | If set, registration requires this password |

## Admin

| Variable | Default | Description |
|----------|---------|-------------|
| `ADMIN_EMAIL` | — | Email address for the admin account |

## Email / SMTP

| Variable | Default | Description |
|----------|---------|-------------|
| `SMTP_HOST` | — | SMTP server hostname (empty = log to stdout) |
| `SMTP_PORT` | `587` | SMTP port |
| `SMTP_USERNAME` | — | SMTP auth username |
| `SMTP_PASSWORD` | — | SMTP auth password |
| `SMTP_FROM` | `noreply@ninerlog.com` | Sender address |

## Notifications

| Variable | Default | Description |
|----------|---------|-------------|
| `NOTIFICATION_CHECK_INTERVAL` | `1h` | How often to check for notifications (Go duration) |

## Backups

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_PATH` | `./backups` | Host directory for backup files |
| `BACKUP_INTERVAL` | `21600` | Seconds between backups (default: 6 hours) |
| `BACKUP_RETENTION` | `30` | Number of compressed backups to keep |

Backups are gzip-compressed `pg_dump` snapshots written to `BACKUP_PATH` on the host. Old backups beyond the retention count are automatically pruned. Point your remote backup tool (rsync, rclone, etc.) at this directory.
