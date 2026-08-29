#!/usr/bin/env bash
# Copy prod (Azure Postgres) → staging (postgres-staging pod on VM).
# Requires: k3s, postgres-staging pod running (see deploy-k8s.sh step 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${REPO_DIR}/.env"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

: "${DB_HOST:?Set DB_HOST in .env}"
: "${DB_USER:?Set DB_USER in .env}"
: "${DB_PASSWORD:?Set DB_PASSWORD in .env}"

DB_PORT="${DB_PORT:-5432}"
PROD_DB="${ODOO_DB_NAME:-odoo_devops_lab}"
STAGING_DB="${ODOO_STAGING_DB_NAME:-odoo_staging}"
STAGING_USER="${STAGING_DB_USER:-odoo}"
STAGING_PASSWORD="${STAGING_DB_PASSWORD:-odoo-staging-change-me}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "[seed] Wait for postgres-staging..."
kubectl -n odoo wait --for=condition=Available deployment/postgres-staging --timeout=120s

echo "[seed] Dump Azure prod ${PROD_DB}..."
sudo docker run --rm \
  -e PGPASSWORD="$DB_PASSWORD" \
  postgres:16 \
  pg_dump -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" -Fc \
  --no-owner --no-acl \
  "$PROD_DB" > "${WORKDIR}/prod.dump"

echo "[seed] Restore into VM postgres-staging (${STAGING_DB})..."
kubectl -n odoo port-forward svc/postgres-staging 15432:5432 >/tmp/pf-staging.log 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null; rm -rf "$WORKDIR"' EXIT
sleep 2

sudo docker run --rm \
  -e PGPASSWORD="$STAGING_PASSWORD" \
  --network host \
  -v "${WORKDIR}:/backup:ro" \
  postgres:16 \
  pg_restore -h 127.0.0.1 -p 15432 -U "$STAGING_USER" \
  -d "${STAGING_DB}" --clean --if-exists --no-owner --no-acl --role="${STAGING_USER}" \
  "/backup/prod.dump"

kill "$PF_PID" 2>/dev/null || true

echo "[seed] Copy filestore ${PROD_DB} → ${STAGING_DB}..."
PROD_FS="/srv/odoo/prod/filestore/${PROD_DB}"
STAGING_FS="/srv/odoo/staging/filestore/${STAGING_DB}"
sudo mkdir -p "$(dirname "$STAGING_FS")"
if [[ -d "$PROD_FS" ]]; then
  sudo rm -rf "${STAGING_FS}"
  sudo cp -a "${PROD_FS}" "${STAGING_FS}"
else
  echo "Warning: prod filestore not at ${PROD_FS} — run migrate-compose-to-k8s.sh first." >&2
fi

echo "[seed] Done. Staging DB on VM postgres-staging pod."
