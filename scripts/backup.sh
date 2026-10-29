#!/usr/bin/env bash
# Production backup: Azure Postgres pg_dump + filestore → Blob (dated + prod filestore container).
#
# Requires: docker, kubectl, az CLI, .env (see .env.azure.example)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_azure_prod_postgres
require_azure_storage

: "${DB_USER:?Set DB_USER in .env}"
: "${DB_PASSWORD:?Set DB_PASSWORD in .env}"

NS="$(odoo_namespace)"
WEB_DEPLOY="${ODOO_WEB_DEPLOYMENT:-odoo-prod-web}"
ODOO_DB_NAME="${ODOO_DB_NAME:-odoo_devops_lab}"
STAMP="$(date +%Y-%m-%d)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "[backup] pg_dump ${ODOO_DB_NAME} @ ${POSTGRES_HOST} (Azure, not PgBouncer)..."
docker run --rm \
  -e PGPASSWORD="$DB_PASSWORD" \
  -e PGSSLMODE="$PGSSLMODE" \
  postgres:16 \
  pg_dump -h "$POSTGRES_HOST" -U "$DB_USER" -p "$DB_PORT" -Fc \
  "$ODOO_DB_NAME" > "${WORKDIR}/db.dump"

POD="$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=odoo-prod,app.kubernetes.io/component=web \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "$POD" ]]; then
  echo "[backup] No odoo-prod-web pod in ${NS}." >&2
  exit 1
fi

echo "[backup] Filestore from pod ${POD}..."
kubectl -n "$NS" exec "$POD" -- \
  tar czf - -C /var/lib/odoo/filestore "${ODOO_DB_NAME}" \
  > "${WORKDIR}/filestore.tar.gz"

export AZURE_STORAGE_KEY
echo "[backup] Upload ${STAMP}/ to ${AZURE_STORAGE_CONTAINER}..."
az storage blob upload \
  --account-name "${AZURE_STORAGE_ACCOUNT}" \
  --container-name "${AZURE_STORAGE_CONTAINER}" \
  --name "${STAMP}/db.dump" \
  --file "${WORKDIR}/db.dump" \
  --overwrite \
  --only-show-errors

az storage blob upload \
  --account-name "${AZURE_STORAGE_ACCOUNT}" \
  --container-name "${AZURE_STORAGE_CONTAINER}" \
  --name "${STAMP}/filestore.tar.gz" \
  --file "${WORKDIR}/filestore.tar.gz" \
  --overwrite \
  --only-show-errors

echo "[backup] Update live prod filestore blob (${ODOO_PROD_FILESTORE_CONTAINER})..."
"${SCRIPT_DIR}/sync-filestore-blob.sh" push prod

echo "[backup] Done: ${AZURE_STORAGE_CONTAINER}/${STAMP}/"
