#!/bin/sh
set -eu

# =============================================================================
# One-time PRIMARY replication setup (idempotent)
# =============================================================================
# Prepares an already-running primary database to feed a streaming standby:
#   1. creates the REPLICATION login role,
#   2. creates a persistent physical replication slot,
#   3. allows replication connections from the standby's tailnet IP in pg_hba,
#   4. reloads the config (no restart, no downtime).
#
# It is safe to run more than once. Run it INSIDE the primary's postgres
# container so it can edit pg_hba.conf in the data directory:
#
#   docker compose -f docker-compose.yml -f deploy/ha/docker-compose.primary.yml \
#     cp scripts/pg-primary-setup.sh postgres:/tmp/pg-primary-setup.sh
#   docker compose -f docker-compose.yml -f deploy/ha/docker-compose.primary.yml \
#     exec \
#       -e REPLICATION_USER="replicator" \
#       -e REPLICATION_PASSWORD="<the replication password>" \
#       -e STANDBY_TAILSCALE_IP="100.x.y.z" \
#       postgres sh /tmp/pg-primary-setup.sh
#
# See docs/HA_SCALING.md.
# -----------------------------------------------------------------------------

POSTGRES_USER="${POSTGRES_USER:-ninerlog}"
REPLICATION_USER="${REPLICATION_USER:-replicator}"
REPLICATION_SLOT="${REPLICATION_SLOT:-standby_slot}"
PGDATA="${PGDATA:-/var/lib/postgresql/18/docker}"

: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD is required}"
: "${STANDBY_TAILSCALE_IP:?STANDBY_TAILSCALE_IP is required (the standby VM's 100.x tailnet address)}"

psql_super() {
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres "$@"
}

echo "[primary-setup] Ensuring replication role '${REPLICATION_USER}'..."
# Create the role if missing; always (re)set the password so reruns are safe.
if [ "$(psql_super -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${REPLICATION_USER}'")" = "1" ]; then
  psql_super -c "ALTER ROLE \"${REPLICATION_USER}\" WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';"
else
  psql_super -c "CREATE ROLE \"${REPLICATION_USER}\" WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';"
fi

echo "[primary-setup] Ensuring physical replication slot '${REPLICATION_SLOT}'..."
psql_super -c "SELECT pg_create_physical_replication_slot('${REPLICATION_SLOT}') \
  WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '${REPLICATION_SLOT}');"

echo "[primary-setup] Ensuring pg_hba.conf allows replication from ${STANDBY_TAILSCALE_IP}..."
HBA_LINE="host replication ${REPLICATION_USER} ${STANDBY_TAILSCALE_IP}/32 scram-sha-256"
HBA_FILE="${PGDATA}/pg_hba.conf"
if grep -qF "$HBA_LINE" "$HBA_FILE" 2>/dev/null; then
  echo "[primary-setup] pg_hba entry already present."
else
  printf '\n# NinerLog HA: streaming replication from the standby region (tailnet)\n%s\n' "$HBA_LINE" >> "$HBA_FILE"
  echo "[primary-setup] pg_hba entry added."
fi

echo "[primary-setup] Reloading configuration..."
psql_super -c "SELECT pg_reload_conf();" >/dev/null

echo "[primary-setup] Done. The standby can now run pg_basebackup and stream."
