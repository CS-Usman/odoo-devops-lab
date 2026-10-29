#!/usr/bin/env bash
# Wipe staging and copy production (Azure Postgres + Blob filestore → cluster staging).
#
# Staging Odoo connects to Service postgres-staging (any VM — cluster DNS).
# Usage: ./scripts/refresh-staging-from-prod.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_azure_prod_postgres
require_azure_storage

: "${DB_USER:?Azure prod DB user}"
: "${DB_PASSWORD:?Azure prod DB password}"
: "${STAGING_DB_PASSWORD:?In-cluster postgres-staging password}"

STAGING_DB_USER="${STAGING_DB_USER:-odoo_staging}"
STAGING_DB="${ODOO_STAGING_DB_NAME:-odoo_staging}"
PROD_DB="${ODOO_DB_NAME:-odoo_devops_lab}"
NS="$(odoo_namespace)"
STAGING_WEB="${STAGING_WEB_DEPLOYMENT:-odoo-staging-web}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "This will DROP staging DB ${STAGING_DB} and replace filestore from production."
read -r -p "Type yes to continue: " confirm
[[ "$confirm" == "yes" ]] || exit 1

wait_postgres_staging
PG_POD="$(postgres_staging_pod)"
[[ -n "$PG_POD" ]] || {
  echo "[refresh] postgres-staging not running. Deploy: ./scripts/deploy-aks-apps.sh or Argo postgres-staging" >&2
  exit 1
}

echo "[refresh] Scale odoo-staging-web to 0..."
kubectl -n "$NS" scale "deployment/${STAGING_WEB}" --replicas=0 2>/dev/null || true
kubectl -n "$NS" wait --for=delete pod -l app.kubernetes.io/name=odoo-staging --timeout=180s 2>/dev/null || true

echo "[refresh] pg_dump prod ${PROD_DB} from Azure ${POSTGRES_HOST}..."
docker run --rm \
  -e PGPASSWORD="$DB_PASSWORD" \
  -e PGSSLMODE="$PGSSLMODE" \
  postgres:16 \
  pg_dump -h "$POSTGRES_HOST" -U "$DB_USER" -p "$DB_PORT" -Fc \
  "$PROD_DB" > "${WORKDIR}/prod.dump"

echo "[refresh] Reset staging DB on pod ${PG_POD} (postgres-staging.${NS}.svc)..."
kubectl -n "$NS" exec "$PG_POD" -- psql -U "$STAGING_DB_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${STAGING_DB}' AND pid <> pg_backend_pid();" \
  -c "DROP DATABASE IF EXISTS ${STAGING_DB};" \
  -c "CREATE DATABASE ${STAGING_DB} OWNER ${STAGING_DB_USER};"

kubectl -n "$NS" exec -i "$PG_POD" -- pg_restore -U "$STAGING_DB_USER" -d "$STAGING_DB" \
  --clean --if-exists --no-owner --no-acl \
  < "${WORKDIR}/prod.dump"

echo "[refresh] Filestore via Blob..."
"${SCRIPT_DIR}/sync-filestore-blob.sh" push prod
"${SCRIPT_DIR}/sync-filestore-blob.sh" copy-prod-to-staging
sleep 5

kubectl -n "$NS" scale "deployment/${STAGING_WEB}" --replicas=1
kubectl -n "$NS" rollout status "deployment/${STAGING_WEB}" --timeout=600s
"${SCRIPT_DIR}/sync-filestore-blob.sh" pull staging

kubectl -n "$NS" rollout restart "deployment/${STAGING_WEB}"
kubectl -n "$NS" rollout status "deployment/${STAGING_WEB}" --timeout=600s

echo "[refresh] Staging updated. Production Azure DB unchanged."
