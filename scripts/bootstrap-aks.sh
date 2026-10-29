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

if ! kubectl -n odoo get secret odoo-db >/dev/null 2>&1; then
  echo "[bootstrap] Run ./scripts/seed-aks-db-secret.sh first." >&2
  exit 1
fi

if [[ -x "${SCRIPT_DIR}/install-external-secrets.sh" ]] && [[ -n "${VAULT_ADDR:-}" ]]; then
  "${SCRIPT_DIR}/install-external-secrets.sh" || echo "[bootstrap] ESO skipped."
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
echo "[bootstrap] Blob filestore / CSI: k8s/storage/README.md"
