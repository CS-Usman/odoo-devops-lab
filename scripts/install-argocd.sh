#!/usr/bin/env bash
# Install Argo CD. Apps: postgres-staging → pgbouncer → odoo-prod → odoo-staging.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ARGO_VALUES="${REPO_DIR}/helm/argocd/values.yaml"
APPS_DIR="${REPO_DIR}/k8s/argocd/applications"

ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
ARGO_RELEASE="${ARGO_RELEASE:-argocd}"

: "${KUBECONFIG:?Set KUBECONFIG or run az aks get-credentials first}"

if ! command -v helm >/dev/null; then
  echo "[argocd] helm not found" >&2
  exit 1
fi

echo "[argocd] Add argo Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo

echo "[argocd] Install Argo CD (namespace=${ARGO_NAMESPACE})..."
helm upgrade --install "$ARGO_RELEASE" argo/argo-cd \
  -n "$ARGO_NAMESPACE" \
  --create-namespace \
  -f "$ARGO_VALUES" \
  --wait --timeout 10m

if [[ -n "${ARGOCD_GITHUB_TOKEN:-}" ]]; then
  echo "[argocd] Register private GitHub repo credentials..."
  kubectl -n "$ARGO_NAMESPACE" create secret generic repo-odoo-devops-lab \
    --from-literal=username=git \
    --from-literal=password="$ARGOCD_GITHUB_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ARGO_NAMESPACE" label secret repo-odoo-devops-lab \
    argocd.argoproj.io/secret-type=repository --overwrite
fi

echo "[argocd] Apply Applications..."
kubectl apply -f "${APPS_DIR}/"

ADMIN_PASS="$(kubectl -n "$ARGO_NAMESPACE" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"

echo ""
echo "[argocd] UI (from laptop):"
echo "  kubectl -n ${ARGO_NAMESPACE} port-forward svc/${ARGO_RELEASE}-server 8081:80"
echo "  http://127.0.0.1:8081  user: admin  pass: ${ADMIN_PASS:-<see secret argocd-initial-admin-secret>}"
