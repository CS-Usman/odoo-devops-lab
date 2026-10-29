#!/usr/bin/env bash
# Sync Odoo filestore between pods and Azure Blob containers.
#
#   ./scripts/sync-filestore-blob.sh push prod
#   ./scripts/sync-filestore-blob.sh pull staging
#   ./scripts/sync-filestore-blob.sh copy-prod-to-staging

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_azure_storage

NS="$(odoo_namespace)"
PROD_DB="${ODOO_DB_NAME:-odoo_devops_lab}"
STAGING_DB="${ODOO_STAGING_DB_NAME:-odoo_staging}"
export AZURE_STORAGE_KEY

action="${1:-}"
target="${2:-}"

pod_for() {
  kubectl -n "$NS" get pods -l "app.kubernetes.io/name=${1},app.kubernetes.io/component=web" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

push_prod() {
  local pod path
  pod="$(pod_for odoo-prod)"
  [[ -n "$pod" ]] || { echo "[blob] No odoo-prod-web pod" >&2; exit 1; }
  path="/var/lib/odoo/filestore/${PROD_DB}"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN
  echo "[blob] ${path} → ${ODOO_PROD_FILESTORE_CONTAINER}/filestore.tar.gz"
  kubectl -n "$NS" exec "$pod" -- tar czf - -C /var/lib/odoo/filestore "${PROD_DB}" > "${work}/filestore.tar.gz"
  az storage blob upload \
    --account-name "$AZURE_STORAGE_ACCOUNT" \
    --container-name "$ODOO_PROD_FILESTORE_CONTAINER" \
    --name "filestore.tar.gz" \
    --file "${work}/filestore.tar.gz" \
    --overwrite \
    --only-show-errors
}

pull_staging() {
  local pod
  pod="$(pod_for odoo-staging)"
  [[ -n "$pod" ]] || { echo "[blob] No odoo-staging-web pod" >&2; exit 1; }
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN
  az storage blob download \
    --account-name "$AZURE_STORAGE_ACCOUNT" \
    --container-name "$ODOO_STAGING_FILESTORE_CONTAINER" \
    --name "filestore.tar.gz" \
    --file "${work}/filestore.tar.gz" \
    --only-show-errors
  echo "[blob] → pod ${pod} filestore/${STAGING_DB}"
  kubectl -n "$NS" exec "$pod" -- rm -rf "/var/lib/odoo/filestore/${STAGING_DB}"
  kubectl -n "$NS" exec "$pod" -- mkdir -p "/var/lib/odoo/filestore/${STAGING_DB}"
  tar xzf "${work}/filestore.tar.gz" -C "${work}"
  src="${work}/${PROD_DB}"
  [[ -d "$src" ]] || src="${work}/${STAGING_DB}"
  [[ -d "$src" ]] || src="${work}/$(tar tzf "${work}/filestore.tar.gz" | head -1 | cut -d/ -f1)"
  kubectl -n "$NS" cp "${src}/." "${NS}/${pod}:/var/lib/odoo/filestore/${STAGING_DB}/"
}

copy_prod_to_staging() {
  echo "[blob] Copy ${ODOO_PROD_FILESTORE_CONTAINER} → ${ODOO_STAGING_FILESTORE_CONTAINER}..."
  az storage blob copy start \
    --account-name "$AZURE_STORAGE_ACCOUNT" \
    --destination-blob "filestore.tar.gz" \
    --destination-container "$ODOO_STAGING_FILESTORE_CONTAINER" \
    --source-account-name "$AZURE_STORAGE_ACCOUNT" \
    --source-container "$ODOO_PROD_FILESTORE_CONTAINER" \
    --source-blob "filestore.tar.gz" \
    --only-show-errors
  echo "[blob] Copy started (async). Wait ~5s before pull staging."
}

case "$action" in
  push)
    [[ "$target" == "prod" ]] || { echo "Usage: $0 push prod" >&2; exit 1; }
    push_prod
    ;;
  pull)
    [[ "$target" == "staging" ]] || { echo "Usage: $0 pull staging" >&2; exit 1; }
    pull_staging
    ;;
  copy-prod-to-staging)
    copy_prod_to_staging
    ;;
  *)
    echo "Usage: $0 push prod | pull staging | copy-prod-to-staging" >&2
    exit 1
    ;;
esac
