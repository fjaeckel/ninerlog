# OIDC Single Sign-On

NinerLog can hand authentication to an external [OpenID Connect](https://openid.net/connect/)
provider — Authentik, Keycloak, Authelia, Zitadel, Microsoft Entra ID, Okta, Google, and
anything else that implements OIDC discovery. Users then sign in through your identity
provider instead of with a NinerLog password.

OIDC is **optional and off by default**. Setting `OIDC_ISSUER` in your `.env` is what
turns it on — and it is a **mode switch**, not an extra sign-in button:

> With `OIDC_ISSUER` set, the identity provider owns every account. NinerLog stops
> accepting passwords, stops letting anyone register, and stops offering TOTP and
> passkeys. Your provider's rules (MFA, offboarding, password policy) apply to everyone,
> with no local back door around them.

If you run NinerLog for a flying club that already has central accounts (Authentik,
Keycloak, Entra ID, Google Workspace, …), this is the feature that lets members use them.
If you don't, you can ignore this document entirely — nothing here affects a deployment
that leaves `OIDC_ISSUER` unset.

---

## How it works

NinerLog implements the standard **authorization code flow with PKCE** as a confidential
client:

```
┌─────────┐  1. "Sign in with SSO"   ┌─────────────┐
│ Browser │─────────────────────────▶│ NinerLog API │
│         │◀── 2. redirect ──────────│  (via nginx) │
└────┬────┘                          └──────▲───────┘
     │ 3. user authenticates                │ 5. exchange code,
     ▼    (password, MFA, …)                │    verify ID token
┌──────────┐  4. redirect back with code    │
│ Identity │────────────────────────────────┘
│ Provider │
└──────────┘
```

1. The browser navigates to `/api/v1/auth/oidc/authorize`; the API mints CSRF state,
   a nonce and a PKCE challenge, then redirects to your provider.
2. The user authenticates at the provider — with whatever factors the provider enforces.
3. The provider redirects back to `/api/v1/auth/oidc/callback` with a one-time code.
4. The API exchanges the code for an ID token server-side, verifies its signature against
   the provider's published keys, and provisions (or updates) the user.
5. The browser lands on the frontend with a single-use handoff code, which it swaps for
   the same access/refresh token pair a password login would produce.

From there, sessions work exactly as in local mode — OIDC only replaces how the *first*
token is obtained. Access and refresh tokens never appear in a URL; the handoff code is
single-use and expires after 60 seconds.

Accounts are created automatically on first login, keyed by the provider's stable subject
identifier (never by email address). On every subsequent login the user's email and
display name are re-synced from the provider. **Whoever your provider lets in gets a
NinerLog logbook** — restrict the application to the right group or realm at the provider;
NinerLog has no allow-list of its own.

For protocol-level detail (token verification, CSRF/replay defenses, endpoint reference),
see the [API repo's OIDC documentation](https://github.com/fjaeckel/ninerlog-api/blob/main/docs/OIDC.md).

---

## Prerequisites

1. **HTTPS.** Your NinerLog instance should be served over HTTPS with a real domain —
   see [HTTPS.md](HTTPS.md). Identity providers generally refuse plain-HTTP redirect
   URIs for confidential clients (except localhost for testing).

2. **An OIDC provider.** Anything that supports OIDC discovery
   (`/.well-known/openid-configuration`) and the authorization-code grant works.
   It does not need to run on the same host, and it does not need to be up when
   NinerLog starts — discovery happens on the first login attempt, so running your
   provider in the same compose stack works regardless of boot order.

3. **A client registration at the provider.** Register NinerLog as a
   **confidential** client (client ID + client secret) using the
   **authorization-code** grant, with this exact redirect URI:

   ```
   https://<your-domain>/api/v1/auth/oidc/callback
   ```

   In this compose stack the frontend nginx proxies `/api/*` to the API container, so
   the API is reachable on the **same domain as the frontend** — you only deal with one
   hostname.

4. **If you already have local users:** read [Migrating an existing deployment](#migrating-an-existing-deployment)
   *before* enabling anything. Local logins stop working the moment OIDC mode is on.

---

## Configuration

Add the following to your `.env` (using `logbook.example.com` as the domain):

```bash
# Required — the presence of OIDC_ISSUER enables OIDC mode
OIDC_ISSUER=https://id.example.com/application/o/ninerlog/
OIDC_CLIENT_ID=ninerlog
OIDC_CLIENT_SECRET=<from your provider>
OIDC_REDIRECT_URL=https://logbook.example.com/api/v1/auth/oidc/callback
OIDC_POST_LOGIN_REDIRECT=https://logbook.example.com/auth/callback

# Optional — label on the sign-in button
OIDC_PROVIDER_NAME=Company SSO
```

- `OIDC_ISSUER` must be the exact issuer URL your provider advertises — the base URL
  whose `/.well-known/openid-configuration` resolves, with no query string or fragment.
- `OIDC_REDIRECT_URL` must match the provider's client registration **byte for byte**
  (scheme, host, port, path).
- `OIDC_POST_LOGIN_REDIRECT` is where the browser lands after a successful login —
  the frontend's callback route on your domain, as shown above.

Then restart the API container so it picks up the new environment:

```bash
docker compose up -d api
```

Confirm the mode in the logs:

```bash
docker compose logs api | grep -i oidc
```

```
level=INFO msg="OIDC mode enabled — local passwords, registration, 2FA and passkeys are disabled"
```

A misconfiguration is fatal at startup rather than silent: if `OIDC_ISSUER` is set and
any other required variable is missing or malformed, the container exits with the
offending variable named (visible in `docker compose logs api`). Half-configured is the
one state that would leave nobody able to sign in.

### All variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OIDC_ISSUER` | — | Issuer URL. **Setting it enables OIDC mode.** |
| `OIDC_CLIENT_ID` | — | Client ID from your provider |
| `OIDC_CLIENT_SECRET` | — | Client secret (confidential client — never reaches the browser) |
| `OIDC_REDIRECT_URL` | — | `https://<your-domain>/api/v1/auth/oidc/callback` |
| `OIDC_POST_LOGIN_REDIRECT` | — | Frontend URL after login: `https://<your-domain>/auth/callback` |
| `OIDC_PROVIDER_NAME` | `Single sign-on` | Label on the sign-in button |
| `OIDC_SCOPES` | `openid profile email` | Extra scopes, only if your provider needs them to release the email claim |
| `OIDC_NAME_CLAIM` | `name` | Claim used as display name (falls back to `name`, `preferred_username`, then the email's local part) |
| `OIDC_LINK_BY_VERIFIED_EMAIL` | `false` | Let a first OIDC login adopt an existing local account with the same verified address — see [Migrating](#migrating-an-existing-deployment) |
| `OIDC_TRUST_EMAIL_VERIFIED` | `false` | Treat addresses as verified when the provider omits the `email_verified` claim. Required for `ADMIN_EMAIL` to work with such providers |
| `OIDC_LOGIN_STATE_TTL` | `10m` | How long a started login stays completable at the provider |
| `OIDC_HANDOFF_TTL` | `60s` | Lifetime of the one-time post-login handoff code |

`WEBAUTHN_*` variables are ignored while OIDC mode is on (passkeys are a local
credential). Everything else — `ADMIN_EMAIL`, `CORS_ORIGIN`, SMTP, backups, monitoring —
keeps working unchanged.

---

## Provider recipes

Each recipe needs `OIDC_REDIRECT_URL` and `OIDC_POST_LOGIN_REDIRECT` as above; only the
provider-specific values are shown. Fuller notes live in the
[API repo's OIDC doc](https://github.com/fjaeckel/ninerlog-api/blob/main/docs/OIDC.md#provider-recipes).

### Authentik

Create an OAuth2/OpenID Provider plus an Application. The redirect URI must be an exact
match, not a regex.

```bash
OIDC_ISSUER=https://auth.example.com/application/o/ninerlog/
OIDC_CLIENT_ID=<Client ID>
OIDC_CLIENT_SECRET=<Client Secret>
OIDC_PROVIDER_NAME=Authentik
```

### Keycloak

Set the client to *Client authentication: On* (confidential) with the standard flow
enabled.

```bash
OIDC_ISSUER=https://kc.example.com/realms/ninerlog
OIDC_CLIENT_ID=ninerlog
OIDC_CLIENT_SECRET=<from the Credentials tab>
OIDC_PROVIDER_NAME=Keycloak
```

### Authelia

Authelia does not emit the `email_verified` claim, so trust must be granted explicitly:

```bash
OIDC_ISSUER=https://auth.example.com
OIDC_CLIENT_ID=ninerlog
OIDC_CLIENT_SECRET=<the plaintext of the configured hash>
OIDC_PROVIDER_NAME=Authelia
OIDC_TRUST_EMAIL_VERIFIED=true
```

### Microsoft Entra ID

Entra does not send `email_verified`, and does not always send `email` — add the `email`
optional claim to the ID token under *Token configuration*, or logins fail.

```bash
OIDC_ISSUER=https://login.microsoftonline.com/<tenant-id>/v2.0
OIDC_CLIENT_ID=<Application (client) ID>
OIDC_CLIENT_SECRET=<client secret value>
OIDC_PROVIDER_NAME=Microsoft
OIDC_TRUST_EMAIL_VERIFIED=true
```

### Google Workspace

```bash
OIDC_ISSUER=https://accounts.google.com
OIDC_CLIENT_ID=<...>.apps.googleusercontent.com
OIDC_CLIENT_SECRET=<...>
OIDC_PROVIDER_NAME=Google
```

Restrict which accounts may sign in on the Google side — NinerLog provisions anyone the
provider lets through.

---

## What changes for users

- The sign-in page shows a single **"Sign in with {your provider}"** button instead of
  the email/password form. Registration, password reset, TOTP and passkey management
  disappear from the UI (the underlying endpoints return `503`).
- Name and email are owned by the provider and re-synced on every login; they can no
  longer be edited in the NinerLog profile. Display preferences (date/time format,
  columns, …) stay editable.
- Logging out ends the NinerLog session only. The provider session is untouched, so
  clicking "sign in" again may sign the user straight back in without a prompt.
- Removing a user at the provider stops them signing in, but does **not** delete their
  logbook — delete the account from the admin panel if that's what you want.

### Administrators

Admin rights still come from `ADMIN_EMAIL`, matched against the (verified) address from
the ID token. If your provider does not emit `email_verified` (Authelia, Entra ID), you
must also set `OIDC_TRUST_EMAIL_VERIFIED=true` or the admin account is provisioned
unverified and `ADMIN_EMAIL` has no effect.

---

## Migrating an existing deployment

If your instance already has local accounts, decide whether an incoming OIDC identity may
**adopt** the existing account with the same email address.

By default it may not: a first OIDC login for an address that already exists fails with
`email_conflict` rather than silently creating a second, empty logbook. That is the safe
default — if users can choose their own email at your provider, adoption would be an
account-takeover path.

To migrate real accounts:

1. Announce a cutover window — local logins stop working the moment you deploy.
2. Make sure every user's provider address matches their NinerLog address exactly.
3. Deploy with the OIDC variables **plus** `OIDC_LINK_BY_VERIFIED_EMAIL=true`.
4. Have everyone sign in once. Adoption happens only when the provider also asserts
   `email_verified: true` for the address (or you set `OIDC_TRUST_EMAIL_VERIFIED=true`
   for providers that omit the claim — only do this if users cannot set arbitrary
   addresses on their own profile there).
5. Optionally set `OIDC_LINK_BY_VERIFIED_EMAIL` back to `false` — once linked, the
   identity mapping is permanent.

Old password hashes, TOTP secrets and passkeys stay in the database untouched and
unusable. If you ever remove `OIDC_ISSUER` again, the server returns to local mode and
those credentials work again; OIDC-provisioned accounts (which have no password) cannot
log in until given one.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| API container restarts, log says `OIDC_CLIENT_ID is required…` | `OIDC_ISSUER` is set but other required variables are missing | Set all five required variables in `.env`, then `docker compose up -d api` |
| Sign-in page still shows the password form | The variables didn't reach the container, or the API wasn't restarted | Confirm `.env` sits next to `docker-compose.yml`, run `docker compose up -d api`, check `docker compose logs api` for the "OIDC mode enabled" line |
| `503` "identity provider is currently unreachable" on login | OIDC discovery failed from inside the container | `docker compose exec api wget -qO- $OIDC_ISSUER/.well-known/openid-configuration` — the issuer must resolve from the container's network, not just from your browser |
| Provider shows `redirect_uri_mismatch` | `OIDC_REDIRECT_URL` differs from the client registration | They must match exactly — scheme, host, port and path |
| Login bounces back with `?oidc_error=invalid_state` | Login window expired, replayed URL, or the state cookie was dropped by a proxy | Retry from the sign-in button; if persistent, check `OIDC_REDIRECT_URL` uses `https` when the site does |
| `?oidc_error=email_missing` | Provider sent no usable `email` claim | Add the `email` scope or configure the claim at the provider (see the Entra recipe) |
| `?oidc_error=email_conflict` | The address belongs to an existing local account | See [Migrating an existing deployment](#migrating-an-existing-deployment) |
| Admin rights not granted | Address provisioned unverified | Set `OIDC_TRUST_EMAIL_VERIFIED=true`, or make the provider emit `email_verified` |

Error codes shown to the browser are deliberately coarse; the detail is always in
`docker compose logs api`. If you run the [monitoring stack](MONITORING.md), the
`auth_oidc_login_attempts_total{result}` metric shows at which step logins are failing.

---

## Security notes

- Authorization-code flow with PKCE on every login; the client secret never leaves the
  API container.
- ID tokens are verified against the provider's published signing keys (issuer, audience,
  expiry, nonce).
- Accounts are matched on the provider's stable subject ID, never on email — an email
  change at the provider cannot claim someone else's logbook.
- Tokens never travel in URLs; the post-login redirect carries only a single-use,
  60-second handoff code, and the database stores only hashes of in-flight login state.
- The provider is a full-trust component: anyone it lets into the application gets an
  account. Do the gatekeeping (groups, realms, tenant restrictions) at the provider.

The full property-by-property breakdown, with pointers into the implementation, is in the
[API repo's OIDC doc](https://github.com/fjaeckel/ninerlog-api/blob/main/docs/OIDC.md#security-properties).

---

## See also

- [`CONFIGURATION.md`](CONFIGURATION.md) — full env-var reference
- [`HTTPS.md`](HTTPS.md) — TLS / Let's Encrypt setup (a prerequisite)
- [`PASSKEYS.md`](PASSKEYS.md) — local-mode passwordless sign-in (mutually exclusive with OIDC)
- [API repo: docs/OIDC.md](https://github.com/fjaeckel/ninerlog-api/blob/main/docs/OIDC.md) — protocol details, endpoint reference, security properties
