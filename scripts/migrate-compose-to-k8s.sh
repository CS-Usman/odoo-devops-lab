#!/usr/bin/env bash
# Move Compose filestore to k8s hostPath dirs before first Helm deploy.
# Usage: ./scripts/migrate-compose-to-k8s.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${REPO_DIR}/docker-compose.azure.yml"
ENV_FILE="${REPO_DIR}/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

PROD_DB="${ODOO_DB_NAME:-odoo_devops_lab}"
PROD_DIR="/srv/odoo/prod"
STAGING_DIR="/srv/odoo/staging"

echo "[migrate] Stop Compose Odoo (keep data on volume)..."
sudo docker compose -f "$COMPOSE_FILE" stop odoo || true

VOLUME_PATH="$(sudo docker volume inspect odoo-devops-lab_odoo-data --format '{{ .Mountpoint }}' 2>/dev/null || true)"

if [[ -n "$VOLUME_PATH" && -d "${VOLUME_PATH}/filestore/${PROD_DB}" ]]; then
  echo "[migrate] Rsync Compose volume → ${PROD_DIR}..."
  sudo mkdir -p "$PROD_DIR"
  sudo rsync -a "${VOLUME_PATH}/" "${PROD_DIR}/"
else
  echo "[migrate] No Compose volume — ensure ${PROD_DIR}/filestore exists." >&2
  sudo mkdir -p "${PROD_DIR}/filestore"
fi

sudo mkdir -p "${STAGING_DIR}/filestore"
sudo chown -R 101:101 "$PROD_DIR" "$STAGING_DIR" 2>/dev/null || sudo chmod -R 777 "$PROD_DIR" "$STAGING_DIR"

echo "[migrate] Done. Prod data: ${PROD_DIR}/filestore/${PROD_DB}"
echo "[migrate] Run ./scripts/seed-staging.sh if staging not seeded yet."
