#!/usr/bin/env bash
# Phase 8 — Download prod backup from Blob and restore into staging (VM postgres-staging).
# Usage: ./scripts/restore-staging.sh YYYY-MM-DD
# WARNING: replaces odoo_staging database and staging filestore.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 YYYY-MM-DD" >&2
  exit 1
fi

STAMP="$1"
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

: "${DB_USER:?Set DB_USER in .env (prod Azure Postgres user — used only for reference)}"
: "${AZURE_STORAGE_ACCOUNT:?Set AZURE_STORAGE_ACCOUNT in .env}"
: "${AZURE_STORAGE_KEY:?Set AZURE_STORAGE_KEY in .env}"

AZURE_STORAGE_CONTAINER="${AZURE_STORAGE_CONTAINER:-odoo-backups}"
PROD_DB="${ODOO_DB_NAME:-odoo_devops_lab}"
STAGING_DB="${ODOO_STAGING_DB_NAME:-odoo_staging}"
STAGING_USER="${STAGING_DB_USER:-odoo}"
STAGING_PASSWORD="${STAGING_DB_PASSWORD:-odoo-staging-change-me}"
STAGING_FS="/srv/odoo/staging/filestore/${STAGING_DB}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "This will REPLACE staging database ${STAGING_DB} and filestore on the VM."
read -r -p "Type yes to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

export AZURE_STORAGE_KEY
echo "[restore-staging] Download ${STAMP}/ from blob..."
az storage blob download \
  --account-name "${AZURE_STORAGE_ACCOUNT}" \
  --container-name "${AZURE_STORAGE_CONTAINER}" \
  --name "${STAMP}/db.dump" \
  --file "${WORKDIR}/db.dump" \
  --only-show-errors

az storage blob download \
  --account-name "${AZURE_STORAGE_ACCOUNT}" \
  --container-name "${AZURE_STORAGE_CONTAINER}" \
  --name "${STAMP}/filestore.tar.gz" \
  --file "${WORKDIR}/filestore.tar.gz" \
  --only-show-errors

echo "[restore-staging] Stop odoo-staging..."
kubectl -n odoo scale deployment odoo-staging --replicas=0
kubectl -n odoo wait --for=delete pod -l app.kubernetes.io/name=odoo-staging --timeout=120s 2>/dev/null || true

echo "[restore-staging] Wait for postgres-staging..."
kubectl -n odoo wait --for=condition=Available deployment/postgres-staging --timeout=120s

echo "[restore-staging] PostgreSQL restore into ${STAGING_DB}..."
kubectl -n odoo port-forward svc/postgres-staging 15432:5432 >/tmp/pf-restore-staging.log 2>&1 &
PF_PID=$!
sleep 3

sudo docker run --rm \
  -e PGPASSWORD="$STAGING_PASSWORD" \
  --network host \
  -v "${WORKDIR}:/backup:ro" \
  postgres:16 \
  pg_restore -h 127.0.0.1 -p 15432 -U "$STAGING_USER" \
  -d "${STAGING_DB}" --clean --if-exists --no-owner --no-acl --role="${STAGING_USER}" \
  "/backup/db.dump"

kill "$PF_PID" 2>/dev/null || true

echo "[restore-staging] Filestore ${PROD_DB} → ${STAGING_DB}..."
sudo rm -rf "${STAGING_FS}"
sudo mkdir -p "$(dirname "$STAGING_FS")"
sudo tar xzf "${WORKDIR}/filestore.tar.gz" -C "$(dirname "$STAGING_FS")"
if [[ -d "$(dirname "$STAGING_FS")/${PROD_DB}" ]]; then
  sudo mv "$(dirname "$STAGING_FS")/${PROD_DB}" "${STAGING_FS}"
fi

echo "[restore-staging] Start odoo-staging..."
kubectl -n odoo scale deployment odoo-staging --replicas=1
kubectl -n odoo rollout status deployment/odoo-staging --timeout=600s

echo "[restore-staging] Health check..."
until curl -sf --max-time 15 http://127.0.0.1:8080/devops/health | grep -qE '"status"[[:space:]]*:[[:space:]]*"ok"'; do
  echo "[restore-staging] waiting for staging..."
  sleep 5
done

echo "[restore-staging] Done."
echo "  Staging: http://$(curl -sf ifconfig.me 2>/dev/null || echo '<VM_IP>'):8080/"
echo "  Verify prod attachments/images copied from backup ${STAMP}."
