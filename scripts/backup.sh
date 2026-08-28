#!/usr/bin/env bash
# Upload PostgreSQL dump + Odoo filestore to Azure Blob.
# Requires: .env with DB_* and AZURE_STORAGE_* vars, az CLI, docker (postgres:16 client).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${REPO_DIR}/.env"
COMPOSE_FILE="${REPO_DIR}/docker-compose.azure.yml"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

: "${DB_HOST:?Set DB_HOST in .env}"
: "${DB_USER:?Set DB_USER in .env}"
: "${DB_PASSWORD:?Set DB_PASSWORD in .env}"
: "${AZURE_STORAGE_ACCOUNT:?Set AZURE_STORAGE_ACCOUNT in .env}"
: "${AZURE_STORAGE_KEY:?Set AZURE_STORAGE_KEY in .env}"

DB_PORT="${DB_PORT:-5432}"
AZURE_STORAGE_CONTAINER="${AZURE_STORAGE_CONTAINER:-odoo-backups}"
ODOO_DB_NAME="${ODOO_DB_NAME:-odoo_devops_lab}"
STAMP="$(date +%Y-%m-%d)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "[backup] PostgreSQL dump of ${ODOO_DB_NAME} (postgres:16 client)..."
sudo docker run --rm \
  -e PGPASSWORD="$DB_PASSWORD" \
  postgres:16 \
  pg_dump -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" -Fc \
  "$ODOO_DB_NAME" > "${WORKDIR}/db.dump"

echo "[backup] Filestore archive..."
VOLUME_NAME="odoo-devops-lab_odoo-data"
VOLUME_PATH="$(sudo docker volume inspect "${VOLUME_NAME}" --format '{{ .Mountpoint }}')"
FILESTORE="${VOLUME_PATH}/filestore/${ODOO_DB_NAME}"

if [[ ! -d "$FILESTORE" ]]; then
  echo "Filestore not found: ${FILESTORE}" >&2
  exit 1
fi

sudo tar czf "${WORKDIR}/filestore.tar.gz" -C "$(dirname "$FILESTORE")" "$(basename "$FILESTORE")"
sudo chown "$(id -u):$(id -g)" "${WORKDIR}/filestore.tar.gz"

echo "[backup] Upload to blob://${AZURE_STORAGE_CONTAINER}/${STAMP}/..."
export AZURE_STORAGE_KEY
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

echo "[backup] Done: ${AZURE_STORAGE_CONTAINER}/${STAMP}/db.dump"
echo "[backup] Done: ${AZURE_STORAGE_CONTAINER}/${STAMP}/filestore.tar.gz"
