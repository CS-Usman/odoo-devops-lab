#!/usr/bin/env bash
# Staging only — live prod copy or dated backup from Blob.
#
#   ./scripts/restore-staging.sh live
#   ./scripts/restore-staging.sh YYYY-MM-DD

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 1 && "$1" == "live" ]]; then
  exec "${SCRIPT_DIR}/refresh-staging-from-prod.sh"
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 live | YYYY-MM-DD" >&2
  exit 1
fi

STAMP="$1"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_azure_storage
: "${STAGING_DB_PASSWORD:?}"

STAGING_DB_USER="${STAGING_DB_USER:-odoo_staging}"
STAGING_DB="${ODOO_STAGING_DB_NAME:-odoo_staging}"
NS="$(odoo_namespace)"
STAGING_WEB="${STAGING_WEB_DEPLOYMENT:-odoo-staging-web}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

wait_postgres_staging
PG_POD="$(postgres_staging_pod)"
[[ -n "$PG_POD" ]] || { echo "[restore] postgres-staging missing" >&2; exit 1; }

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

kubectl -n "$NS" scale "deployment/${STAGING_WEB}" --replicas=0 2>/dev/null || true

kubectl -n "$NS" exec "$PG_POD" -- psql -U "$STAGING_DB_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS ${STAGING_DB};" \
  -c "CREATE DATABASE ${STAGING_DB} OWNER ${STAGING_DB_USER};"

kubectl -n "$NS" exec -i "$PG_POD" -- pg_restore -U "$STAGING_DB_USER" -d "$STAGING_DB" \
  --clean --if-exists --no-owner --no-acl \
  < "${WORKDIR}/db.dump"

kubectl -n "$NS" scale "deployment/${STAGING_WEB}" --replicas=1
kubectl -n "$NS" rollout status "deployment/${STAGING_WEB}" --timeout=600s

POD="$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=odoo-staging,app.kubernetes.io/component=web \
  -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "$NS" exec "$POD" -- rm -rf "/var/lib/odoo/filestore/${STAGING_DB}"
kubectl -n "$NS" exec "$POD" -- mkdir -p "/var/lib/odoo/filestore/${STAGING_DB}"
tar xzf "${WORKDIR}/filestore.tar.gz" -C "${WORKDIR}"
SRC="${WORKDIR}/$(tar tzf "${WORKDIR}/filestore.tar.gz" | head -1 | cut -d/ -f1)"
kubectl -n "$NS" cp "${SRC}/." "${NS}/${POD}:/var/lib/odoo/filestore/${STAGING_DB}/"

echo "[restore] Staging loaded from backup ${STAMP} (prod Azure untouched)."
