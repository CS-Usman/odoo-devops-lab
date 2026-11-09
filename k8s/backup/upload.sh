#!/usr/bin/env bash
# Upload /work artifacts to Azure Blob (Odoo backup CronJob upload container).
set -euo pipefail

: "${AZURE_CLIENT_ID:?}"
: "${AZURE_STORAGE_ACCOUNT:?}"
: "${AZURE_STORAGE_CONTAINER:?}"
: "${ODOO_PROD_FILESTORE_CONTAINER:?}"
: "${WORKDIR:?}"

STAMP="${BACKUP_STAMP:-$(date -u +%Y-%m-%d)}"

echo "[backup] Azure login (workload identity)..."
az login --identity -o none

upload() {
  local container="$1" blob="$2" file="$3"
  echo "[backup] blob ${container}/${blob}"
  az storage blob upload \
    --auth-mode login \
    --account-name "$AZURE_STORAGE_ACCOUNT" \
    --container-name "$container" \
    --name "$blob" \
    --file "$file" \
    --overwrite \
    --only-show-errors
}

upload "$AZURE_STORAGE_CONTAINER" "${STAMP}/db.dump" "${WORKDIR}/db.dump"
upload "$AZURE_STORAGE_CONTAINER" "${STAMP}/filestore.tar.gz" "${WORKDIR}/filestore.tar.gz"
upload "$ODOO_PROD_FILESTORE_CONTAINER" "filestore.tar.gz" "${WORKDIR}/filestore.tar.gz"

echo "[backup] Done: ${AZURE_STORAGE_CONTAINER}/${STAMP}/"
