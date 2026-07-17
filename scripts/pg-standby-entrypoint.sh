#!/bin/sh
set -e

# =============================================================================
# PostgreSQL streaming HOT-STANDBY entrypoint (HA standby region)
# =============================================================================
# On first boot (empty data directory) this seeds the standby from the primary
# with pg_basebackup over the tailnet, wires up primary_conninfo + a replication
# slot, and drops a standby.signal so Postgres starts in recovery. On every
# subsequent boot the data directory already exists, so it just starts Postgres,
# which reconnects and resumes streaming.
#
# It mirrors pg-init-ssl.sh for wire-encryption certs (pg_basebackup copies the
# primary's *data*, not the out-of-tree /var/lib/postgresql/ssl certs), then
# hands off to the stock docker-entrypoint.sh, which detects the populated data
# directory and starts Postgres without re-running initdb.
#
# Required environment (see deploy/ha/.env.ha.example):
#   PRIMARY_HOST          primary's tailnet address (100.x.y.z or MagicDNS name)
#   REPLICATION_USER      replication role created by scripts/pg-primary-setup.sh
#   REPLICATION_PASSWORD  that role's password
# Optional:
#   PRIMARY_PORT          default 5432
#   REPLICATION_SLOT      default standby_slot (must match pg-primary-setup.sh)
# -----------------------------------------------------------------------------

PGDATA="${PGDATA:-/var/lib/postgresql/18/docker}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"
REPLICATION_SLOT="${REPLICATION_SLOT:-standby_slot}"

# --- 1. Wire-encryption certificate (same as the primary's pg-init-ssl.sh) ---
CERT_DIR="/var/lib/postgresql/ssl"
CERT="$CERT_DIR/server.crt"
KEY="$CERT_DIR/server.key"
if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
  echo "[standby] Generating self-signed TLS certificate for PostgreSQL..."
  mkdir -p "$CERT_DIR"
  openssl req -new -x509 -days 3650 -nodes \
    -out "$CERT" -keyout "$KEY" -subj "/CN=ninerlog-db-standby" 2>/dev/null
  chmod 600 "$KEY"
  chown 70:70 "$CERT" "$KEY"   # UID/GID 70 = postgres in alpine
else
  chmod 600 "$KEY"
  chown 70:70 "$CERT" "$KEY" 2>/dev/null || true
fi

# --- 2. Seed from the primary on first boot -------------------------------
if [ -s "$PGDATA/PG_VERSION" ]; then
  echo "[standby] Data directory already initialised — resuming replication."
else
  : "${PRIMARY_HOST:?PRIMARY_HOST is required to seed the standby}"
  : "${REPLICATION_USER:?REPLICATION_USER is required to seed the standby}"
  : "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD is required to seed the standby}"

  echo "[standby] Empty data directory — running pg_basebackup from ${PRIMARY_HOST}:${PRIMARY_PORT}..."
  mkdir -p "$PGDATA"
  rm -rf "${PGDATA:?}/"* 2>/dev/null || true

  # -R writes standby.signal + a primary_conninfo (without the password);
  # -C -S creates the physical slot if it does not already exist.
  PGPASSWORD="$REPLICATION_PASSWORD" PGSSLMODE=require pg_basebackup \
    --host="$PRIMARY_HOST" \
    --port="$PRIMARY_PORT" \
    --username="$REPLICATION_USER" \
    --pgdata="$PGDATA" \
    --wal-method=stream \
    --write-recovery-conf \
    --create-slot --slot="$REPLICATION_SLOT" \
    --checkpoint=fast \
    --progress --no-password

  # pg_basebackup's -R omits the password; append a fully-specified
  # primary_conninfo (last value wins in postgresql.auto.conf) so the running
  # walreceiver can authenticate unattended.
  {
    echo "primary_conninfo = 'host=${PRIMARY_HOST} port=${PRIMARY_PORT} user=${REPLICATION_USER} password=${REPLICATION_PASSWORD} sslmode=require application_name=ninerlog_standby'"
    echo "primary_slot_name = '${REPLICATION_SLOT}'"
  } >> "$PGDATA/postgresql.auto.conf"
  touch "$PGDATA/standby.signal"

  chown -R 70:70 "$PGDATA"
  chmod 700 "$PGDATA"
  echo "[standby] Base backup complete — starting in hot-standby mode."
fi

# --- 3. Hand off to the stock entrypoint (skips initdb; data dir exists) ---
exec docker-entrypoint.sh "$@"
