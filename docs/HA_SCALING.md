# High Availability & Scaling — Two Regions, Active-Passive

This guide describes running NinerLog across **two VMs in different localities**
for redundancy and disaster recovery, with a **PostgreSQL read replica** and a
full frontend/backend stack in each region, fronted by **DNS-based failover**.

It is deliberately kept **out of the default stack**. The base
`docker-compose.yml` is the single-VM configuration everyone runs. The HA
topology is layered on with the opt-in overlays in [`deploy/ha/`](../deploy/ha/),
applied per-VM with explicit `-f` flags. Nobody who doesn't want HA has to think
about any of this.

> **Read this section first — it shapes everything below.**
>
> Three properties of the current application decide the topology. They are not
> deployment choices; they are facts about the images you run today.
>
> 1. **Docker Compose orchestrates one host.** There is no single override that
>    "spans" two VMs. Each VM runs its own Compose project; the two are joined
>    by the network (your tailnet) and by Postgres streaming replication — not
>    by Compose.
> 2. **The API uses a single `DATABASE_URL`** (no read/write split). A read
>    replica therefore **cannot offload application reads today** — the app has
>    nowhere to send read-only queries. The replica's value here is a **warm
>    standby for failover** plus **local backups**, not read scaling. If the API
>    later gains a read endpoint, the standby can start serving local reads with
>    no topology change.
> 3. **The API runs a singleton in-process scheduler** (cloud-backup + notification
>    dispatch — see [CLOUD_BACKUPS.md](CLOUD_BACKUPS.md)). Running **two active
>    API instances would double every scheduled email and backup upload.** So the
>    two regions must **not** both serve writes at once.
>
> Together these mean the correct shape is **active-passive**: one region is the
> live read-write primary; the other is a warm standby (replicating database +
> a dormant app tier) that you promote on failover. Active-active would require
> app-side changes first (scheduler leader-election and read/write DB routing).

## Topology

```
                         GeoDNS / health-checked DNS failover
                    (users resolve to the healthy region's public IP)
                                      │
                 ┌────────────────────┴─────────────────────┐
                 ▼                                           ▼
   ┌─────────── Region A (PRIMARY) ──────────┐  ┌────────── Region B (STANDBY) ──────────┐
   │  frontend (nginx :80/:443)  ── serving  │  │  frontend  ── dormant (failover profile)│
   │  api (:3000, scheduler ON)  ── serving  │  │  api       ── dormant (scheduler OFF)   │
   │  postgres  PRIMARY (read-write)         │  │  postgres  HOT STANDBY (read-only)      │
   │  postgres-exporter · db-backup · certbot│  │  postgres-exporter · db-backup (replica)│
   └───────────────┬─────────────────────────┘  └──────────────▲─────────────────────────┘
                   │      PostgreSQL streaming replication      │
                   └──────────────  over the tailnet  ──────────┘
                        (primary publishes :5432 on its 100.x IP only)
```

- **Region A (primary)** is the ordinary single-VM stack. It additionally
  publishes Postgres on its **Tailscale IP only** so B can replicate.
- **Region B (standby)** runs a **streaming hot-standby** Postgres that is
  continuously seeded from A. Its **app tier (frontend/api/certbot) stays
  stopped** during normal operation — gated behind a Compose `failover` profile
  — so only one scheduler ever runs. `postgres-exporter` and `db-backup` do run
  on B, giving you replication-lag alerts and a second, independent backup copy.
- **DNS failover** points users at A while A is healthy and at B when A is down.
  Because each region terminates TLS locally on its own public IP, there is no
  central load balancer to become a single point of failure and no extra WAN
  hop. (If you prefer a real L7 load balancer or a managed cloud LB instead of
  GeoDNS, the per-region stacks are identical — only what sits in front changes.)
- **The tailnet is the private backplane.** Replication rides Tailscale
  (WireGuard); Postgres is never bound to a public interface.

## Prerequisites

- Two VMs, each already running the base NinerLog stack, **both joined to the
  same tailnet**. Note each VM's `100.x.y.z` address (`tailscale ip -4`).
- A domain with a DNS provider that supports **health-checked failover** (or
  latency/geo routing), e.g. Cloudflare, Route 53, NS1, deSEC.
- Ports 80/443 open to the public on **both** VMs (for user traffic + ACME).
  Postgres 5432 stays closed on the public NIC on both.

## 1. Configure environment

On **both** VMs, keep the existing `.env` (same `POSTGRES_PASSWORD`, `JWT_SECRET`,
`REFRESH_SECRET`, `TLS_DOMAIN`, `CORS_ORIGIN`, …). Then append the HA variables
from [`deploy/ha/.env.ha.example`](../deploy/ha/.env.ha.example):

- **Both VMs:** `REPLICATION_USER`, `REPLICATION_PASSWORD`, `REPLICATION_SLOT`
  (identical on both).
- **Primary only:** `PRIMARY_TAILSCALE_IP` — the primary's own `100.x` address.
- **Standby only:** `PRIMARY_HOST` — the primary's `100.x` address (or MagicDNS
  name) as reached from the standby.

The two stacks must share the same `POSTGRES_PASSWORD` (the replica is a
byte-for-byte copy of the primary, `ninerlog` role included) and the same
`TLS_DOMAIN` (both serve the same hostname).

## 2. Bring up the primary

On **Region A**:

```bash
docker compose \
  -f docker-compose.yml \
  -f deploy/ha/docker-compose.primary.yml \
  up -d
```

This is the normal stack plus one change: Postgres `:5432` is now published on
`PRIMARY_TAILSCALE_IP` only. Verify it is **not** public:

```bash
ss -tlnp | grep ':5432'
# 100.101.102.103:5432   ✓  (tailnet only)
# 0.0.0.0:5432           ✗  (public — wrong, check PRIMARY_TAILSCALE_IP)
```

## 3. Enable replication on the primary (one-time, no downtime)

Create the replication role + slot and open a single `pg_hba` line for the
standby's tailnet IP. The helper is idempotent:

```bash
BASE="-f docker-compose.yml -f deploy/ha/docker-compose.primary.yml"

docker compose $BASE cp scripts/pg-primary-setup.sh postgres:/tmp/pg-primary-setup.sh
docker compose $BASE exec \
  -e REPLICATION_USER="replicator" \
  -e REPLICATION_PASSWORD="<REPLICATION_PASSWORD from .env>" \
  -e STANDBY_TAILSCALE_IP="100.b.b.b" \
  postgres sh /tmp/pg-primary-setup.sh
```

Streaming replication needs no `wal_level`/`max_wal_senders` tuning — PostgreSQL
18's defaults (`wal_level=replica`, 10 WAL senders, 10 slots) already support it,
and the persistent slot created above stops the primary from recycling WAL the
standby still needs.

## 4. Bring up the standby (seeds itself from the primary)

On **Region B**:

```bash
docker compose \
  -f docker-compose.yml \
  -f deploy/ha/docker-compose.standby.yml \
  up -d
```

On first boot the standby's Postgres image runs `pg_basebackup` against
`PRIMARY_HOST` over the tailnet, writes `standby.signal` + `primary_conninfo`,
and starts streaming. The app tier (frontend/api/certbot) stays **stopped** —
that is intentional. Confirm replication is healthy:

```bash
# On the PRIMARY — one row per connected standby, state should be 'streaming':
docker compose -f docker-compose.yml -f deploy/ha/docker-compose.primary.yml \
  exec postgres psql -U ninerlog -c \
  "SELECT application_name, state, sync_state, replay_lag FROM pg_stat_replication;"

# On the STANDBY — should report it is in recovery:
docker compose -f docker-compose.yml -f deploy/ha/docker-compose.standby.yml \
  exec postgres psql -U ninerlog -c "SELECT pg_is_in_recovery();"   # → t
```

Watch replication lag via the standby's `postgres-exporter`
(`pg_stat_replication` / `pg_replication` series — see [MONITORING.md](MONITORING.md)).

## 5. TLS certificates in both regions

Both regions serve the same `TLS_DOMAIN`, but only the region currently in DNS
can answer an HTTP-01 ACME challenge. Two ways to keep the **standby's** cert
valid while it is out of rotation:

- **DNS-01 challenge (recommended).** Issue/renew via your DNS provider's API so
  it works regardless of which region DNS points at. Run certbot's DNS plugin on
  each VM; this replaces the HTTP-01 flow in [HTTPS.md](HTTPS.md).
- **Tailnet cert-sync.** Let the primary renew normally (HTTP-01, it is in DNS)
  and periodically copy `/etc/letsencrypt` to the standby over the tailnet
  (`tailscale`-scoped `rsync`/`scp` on a cron). Simple, no DNS-provider
  credentials, at the cost of a copy job.

The primary's own certs continue to renew exactly as documented in
[HTTPS.md](HTTPS.md).

## 6. DNS failover

Create a health-checked DNS record for `TLS_DOMAIN` with your provider:

- **Primary target:** Region A's public IP, health check `https://<domain>/health`.
- **Failover target:** Region B's public IP.

While A's health check passes, users resolve to A. When it fails, DNS serves B.
Keep the record **TTL low** (30–60 s) so failover propagates quickly. DNS
failover is not instantaneous — budget for TTL + your provider's check interval.

## Failover runbook (promote the standby)

When Region A is lost, promote B to a read-write primary and start its app tier.

```bash
BASE="-f docker-compose.yml -f deploy/ha/docker-compose.standby.yml"

# 1. Promote the replica to a standalone primary (exits recovery, becomes writable).
docker compose $BASE exec postgres pg_ctl promote -D "$PGDATA"
docker compose $BASE exec postgres psql -U ninerlog -c "SELECT pg_is_in_recovery();"  # → f

# 2. Start the app tier on B (enables the failover profile: api + frontend + certbot).
docker compose $BASE --profile failover up -d

# 3. Flip DNS to Region B (automatic if you configured health-checked failover).
```

Region B's `api` uses the base `DATABASE_URL` (`@postgres:5432`), which now
points at its **own, promoted** database — so it serves reads and writes locally,
and its scheduler is the **only** one running. The topology is now a healthy
single region.

### Failback (return to Region A)

Once Region A's VM is healthy again, it must be **rebuilt as a fresh standby of
B** — do not just restart A's old primary, or you will have two divergent
primaries (split brain).

1. On A: stop the app tier and reset A's database to replicate from B.
   Point-in-time-safe options are `pg_rewind` (if A shut down cleanly) or a fresh
   `pg_basebackup` from B. The simplest reliable reset:

   ```bash
   PRI="-f docker-compose.yml -f deploy/ha/docker-compose.primary.yml"
   docker compose $PRI down
   docker volume rm ninerlog-dockerized_postgres_data   # discard A's stale data
   ```

   Then run A with the **standby** overlay (pointing `PRIMARY_HOST` at B) so it
   re-seeds from the current primary, exactly like step 4 above.
2. When A is caught up and streaming from B, schedule a maintenance window and
   fail back by promoting A and re-pointing DNS — the mirror image of the
   failover runbook.

Because failback involves discarding the stale primary's divergent WAL, always
confirm B's backups (`db-backup`, and cloud backups) are current before you
begin.

## What this does and does not give you

**Does:**

- Survives the loss of an entire locality with a warm, already-replicating
  database and a pre-staged app tier — recovery is a promote + DNS flip, not a
  restore-from-backup.
- A second, independent backup copy and replication-lag monitoring in Region B
  at all times.
- Postgres wire traffic (replication and the app↔db link) never touches the
  public internet.

**Does not (yet):**

- **Scale reads across regions.** The API has one `DATABASE_URL`; the replica
  can't take application reads until the app supports a read endpoint.
- **Serve both regions at once (active-active).** The singleton scheduler makes
  that unsafe without app-side leader-election. Both regions live and writing =
  duplicate notification emails and backup uploads.
- **Fail over with zero data loss.** Streaming replication is asynchronous, so a
  hard primary loss can drop the last few in-flight transactions. Set
  `synchronous_commit`/synchronous replication only if you accept the write-latency
  cost of a cross-locality round trip on every commit.
```
