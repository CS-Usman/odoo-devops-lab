#!/usr/bin/env bash
# Download a backup set from Azure Blob and restore PostgreSQL + filestore.
# Usage: ./scripts/restore.sh 2026-08-28
# WARNING: overwrites the current database and filestore for ODOO_DB_NAME.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 YYYY-MM-DD" >&2
  exit 1
fi

STAMP="$1"
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
VOLUME_NAME="odoo-devops-lab_odoo-data"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "This will REPLACE database ${ODOO_DB_NAME} and its filestore."
read -r -p "Type yes to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

export AZURE_STORAGE_KEY
echo "[restore] Download ${STAMP}/..."
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

echo "[restore] Stop Odoo..."
sudo docker compose -f "${COMPOSE_FILE}" stop odoo

echo "[restore] PostgreSQL restore (postgres:16 client)..."
sudo docker run --rm \
  -e PGPASSWORD="$DB_PASSWORD" \
  -v "${WORKDIR}:/backup:ro" \
  postgres:16 \
  pg_restore -h "$DB_HOST" -U "$DB_USER" -p "$DB_PORT" \
  -d "${ODOO_DB_NAME}" --clean --if-exists --no-owner --role="${DB_USER}" \
  "/backup/db.dump"

VOLUME_PATH="$(sudo docker volume inspect "${VOLUME_NAME}" --format '{{ .Mountpoint }}')"
FILESTORE_DIR="${VOLUME_PATH}/filestore"
sudo rm -rf "${FILESTORE_DIR}/${ODOO_DB_NAME}"
sudo mkdir -p "${FILESTORE_DIR}"
sudo tar xzf "${WORKDIR}/filestore.tar.gz" -C "${FILESTORE_DIR}"

echo "[restore] Start Odoo..."
sudo docker compose -f "${COMPOSE_FILE}" start odoo

echo "[restore] Done. Open Odoo and verify attachments."
