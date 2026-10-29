#!/usr/bin/env bash
# Restore PRODUCTION from dated backup in Blob (Azure Postgres + prod pods).
# Usage: ./scripts/restore.sh YYYY-MM-DD
# Does not touch staging (in-cluster Postgres).

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 YYYY-MM-DD" >&2
  exit 1
fi

STAMP="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_azure_prod_postgres
require_azure_storage

: "${DB_USER:?}"
: "${DB_PASSWORD:?}"

NS="$(odoo_namespace)"
WEB_DEPLOY="${ODOO_WEB_DEPLOYMENT:-odoo-prod-web}"
CRON_DEPLOY="${ODOO_CRON_DEPLOYMENT:-odoo-prod-cron}"
ODOO_DB_NAME="${ODOO_DB_NAME:-odoo_devops_lab}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "This will REPLACE production DB ${ODOO_DB_NAME} and prod filestore."
read -r -p "Type yes to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || exit 1

export AZURE_STORAGE_KEY
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

echo "[restore] Scale prod Odoo to 0..."
kubectl -n "$NS" scale "deployment/${WEB_DEPLOY}" --replicas=0
kubectl -n "$NS" scale "deployment/${CRON_DEPLOY}" --replicas=0
kubectl -n "$NS" wait --for=delete pod -l app.kubernetes.io/name=odoo-prod --timeout=300s 2>/dev/null || true

echo "[restore] pg_restore → Azure ${POSTGRES_HOST}..."
docker run --rm -i \
  -e PGPASSWORD="$DB_PASSWORD" \
  -e PGSSLMODE="$PGSSLMODE" \
  postgres:16 \
  pg_restore -h "$POSTGRES_HOST" -U "$DB_USER" -p "$DB_PORT" \
  -d "${ODOO_DB_NAME}" --clean --if-exists --no-owner --role="${DB_USER}" \
  < "${WORKDIR}/db.dump"

kubectl -n "$NS" scale "deployment/${WEB_DEPLOY}" --replicas=1
kubectl -n "$NS" rollout status "deployment/${WEB_DEPLOY}" --timeout=600s
POD="$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=odoo-prod,app.kubernetes.io/component=web \
  -o jsonpath='{.items[0].metadata.name}')"

echo "[restore] Filestore → pod ${POD}..."
kubectl -n "$NS" exec "$POD" -- rm -rf "/var/lib/odoo/filestore/${ODOO_DB_NAME}"
kubectl -n "$NS" exec "$POD" -- mkdir -p "/var/lib/odoo/filestore/${ODOO_DB_NAME}"
tar xzf "${WORKDIR}/filestore.tar.gz" -C "${WORKDIR}"
SRC="${WORKDIR}/${ODOO_DB_NAME}"
[[ -d "$SRC" ]] || SRC="${WORKDIR}/$(tar tzf "${WORKDIR}/filestore.tar.gz" | head -1 | cut -d/ -f1)"
kubectl -n "$NS" cp "${SRC}/." "${NS}/${POD}:/var/lib/odoo/filestore/${ODOO_DB_NAME}/"

kubectl -n "$NS" scale "deployment/${WEB_DEPLOY}" --replicas=2
kubectl -n "$NS" scale "deployment/${CRON_DEPLOY}" --replicas=1
kubectl -n "$NS" rollout status "deployment/${WEB_DEPLOY}" --timeout=600s
kubectl -n "$NS" rollout status "deployment/${CRON_DEPLOY}" --timeout=600s

"${SCRIPT_DIR}/sync-filestore-blob.sh" push prod
echo "[restore] Done."
