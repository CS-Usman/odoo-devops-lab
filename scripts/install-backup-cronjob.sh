#!/usr/bin/env bash
# Install Odoo production backup CronJob (workload identity → Azure Blob).
#
#   terraform apply
#   ./scripts/install-backup-cronjob.sh
#
# Requires: kubectl, terraform outputs, odoo-db secret, PVC odoo-prod-filestore-rwx.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${REPO_DIR}/k8s/backup"
NS="${ODOO_NAMESPACE:-odoo}"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
require_kubeconfig

CLIENT_ID="${BACKUP_MANAGED_IDENTITY_CLIENT_ID:-}"
STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
if [[ -d "${REPO_DIR}/terraform" ]]; then
  [[ -z "$CLIENT_ID" ]] && CLIENT_ID="$(terraform -chdir="${REPO_DIR}/terraform" output -raw backup_managed_identity_client_id 2>/dev/null || true)"
  [[ -z "$STORAGE_ACCOUNT" ]] && STORAGE_ACCOUNT="$(terraform -chdir="${REPO_DIR}/terraform" output -raw storage_account_name 2>/dev/null || true)"
fi

: "${CLIENT_ID:?Run terraform apply or set BACKUP_MANAGED_IDENTITY_CLIENT_ID}"
: "${STORAGE_ACCOUNT:?Run terraform apply or set AZURE_STORAGE_ACCOUNT}"

if ! kubectl -n "$NS" get secret odoo-db >/dev/null 2>&1; then
  echo "[backup-cron] Missing secret odoo-db in ${NS}. Run ESO / seed-keyvault-secrets first." >&2
  exit 1
fi

if ! kubectl -n "$NS" get pvc odoo-prod-filestore-rwx >/dev/null 2>&1; then
  echo "[backup-cron] Missing PVC odoo-prod-filestore-rwx (deploy odoo-prod first)." >&2
  exit 1
fi

echo "[backup-cron] Label namespace ${NS} for workload identity..."
kubectl label namespace "$NS" azure-workload-identity-use=true --overwrite

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

sed \
  -e "s/CLIENT_ID_PLACEHOLDER/${CLIENT_ID}/g" \
  -e "s/STORAGE_ACCOUNT_PLACEHOLDER/${STORAGE_ACCOUNT}/g" \
  "${BACKUP_DIR}/serviceaccount.yaml" > "${tmp}/serviceaccount.yaml"
sed \
  -e "s/CLIENT_ID_PLACEHOLDER/${CLIENT_ID}/g" \
  -e "s/STORAGE_ACCOUNT_PLACEHOLDER/${STORAGE_ACCOUNT}/g" \
  "${BACKUP_DIR}/configmap.yaml" > "${tmp}/configmap.yaml"

kubectl apply -f "${tmp}/serviceaccount.yaml" -f "${tmp}/configmap.yaml"
kubectl apply -k "${BACKUP_DIR}"

echo "[backup-cron] Installed. Test: kubectl -n ${NS} create job --from=cronjob/odoo-backup odoo-backup-test-\$(date +%s)"
