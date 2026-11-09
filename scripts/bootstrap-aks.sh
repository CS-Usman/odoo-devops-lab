#!/usr/bin/env bash
# First-time AKS platform bootstrap after terraform apply.
#
#   ./scripts/seed-aks-db-secret.sh
#   ./scripts/bootstrap-aks.sh
#   ./scripts/install-argocd.sh && kubectl apply -f k8s/argocd/applications/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

RG="${AZURE_RG:-rg-odoo-devops-lab}"
AKS="${AKS_CLUSTER_NAME:-aks-odoo-devops-lab}"

echo "[bootstrap] kubeconfig (${AKS})..."
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing

kubectl create namespace odoo --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

SECRETS_BACKEND="${SECRETS_BACKEND:-azure-kv}"
KV_URI=""
if [[ -d "${REPO_DIR}/terraform" ]]; then
  KV_URI="$(terraform -chdir="${REPO_DIR}/terraform" output -raw key_vault_uri 2>/dev/null || true)"
fi

if [[ "$SECRETS_BACKEND" == "azure-kv" ]] && [[ -n "$KV_URI" ]] && [[ -x "${SCRIPT_DIR}/install-external-secrets-azure.sh" ]]; then
  if ! kubectl -n odoo get secret odoo-db >/dev/null 2>&1; then
    if [[ -x "${SCRIPT_DIR}/seed-keyvault-secrets.sh" ]]; then
      echo "[bootstrap] Key Vault → ./scripts/seed-keyvault-secrets.sh then re-run bootstrap (or run install-external-secrets-azure.sh after seeding)."
      if [[ -z "${DB_PASSWORD:-}" ]]; then
        echo "[bootstrap] Or: SECRETS_BACKEND=k8s ./scripts/seed-aks-db-secret.sh" >&2
        exit 1
      fi
      "${SCRIPT_DIR}/seed-keyvault-secrets.sh"
    fi
  fi
  "${SCRIPT_DIR}/install-external-secrets-azure.sh"
elif [[ -x "${SCRIPT_DIR}/install-external-secrets.sh" ]] && [[ -n "${VAULT_ADDR:-}" ]]; then
  "${SCRIPT_DIR}/install-external-secrets.sh" || echo "[bootstrap] Vault ESO skipped."
else
  if ! kubectl -n odoo get secret odoo-db >/dev/null 2>&1; then
    echo "[bootstrap] Run ./scripts/seed-aks-db-secret.sh or seed Key Vault (see docs/secrets/README.md)." >&2
    exit 1
  fi
fi

"${SCRIPT_DIR}/deploy-aks-apps.sh"

echo ""
echo "[bootstrap] GitOps (recommended):"
echo "  ./scripts/install-argocd.sh"
echo "  kubectl apply -f k8s/argocd/applications/"
echo ""
echo "[bootstrap] Load staging from prod:"
echo "  ./scripts/refresh-staging-from-prod.sh"
echo ""
echo "[bootstrap] Ingress: ./scripts/install-ingress.sh  (docs/aks/INGRESS.md)"
echo "[bootstrap] Blob filestore / CSI: k8s/storage/README.md"
