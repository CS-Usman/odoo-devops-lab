#!/usr/bin/env bash
# Phase 8B — Install Argo CD and register odoo-staging Application.
# Run on VM after k3s + odoo namespace exist.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ARGO_VALUES="${REPO_DIR}/helm/argocd/values.yaml"
APP_TEMPLATE="${REPO_DIR}/k8s/argocd/applications/odoo-staging.yaml"

ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
ARGO_RELEASE="${ARGO_RELEASE:-argocd}"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

if ! command -v helm >/dev/null; then
  echo "[argocd] helm not found" >&2
  exit 1
fi

DOCKER_GID="$(getent group docker | cut -d: -f3 || echo "999")"
echo "[argocd] Docker supplementalGroup for Odoo chart: ${DOCKER_GID}"

echo "[argocd] Add argo Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo

echo "[argocd] Install Argo CD (namespace=${ARGO_NAMESPACE})..."
helm upgrade --install "$ARGO_RELEASE" argo/argo-cd \
  -n "$ARGO_NAMESPACE" \
  --create-namespace \
  -f "$ARGO_VALUES" \
  --wait \
  --timeout 10m

echo "[argocd] Wait for server..."
kubectl -n "$ARGO_NAMESPACE" rollout status deployment/"${ARGO_RELEASE}-server" --timeout=300s

if [[ -n "${ARGOCD_GITHUB_TOKEN:-}" ]]; then
  echo "[argocd] Add private GitHub repo credentials..."
  kubectl -n "$ARGO_NAMESPACE" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-odoo-devops-lab
  namespace: ${ARGO_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/CS-Usman/odoo-devops-lab
  username: git
  password: ${ARGOCD_GITHUB_TOKEN}
EOF
fi

echo "[argocd] Wait for Application CRD..."
deadline=$((SECONDS + 120))
until kubectl get crd applications.argoproj.io >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "[argocd] Timed out waiting for Application CRD" >&2
    exit 1
  fi
  sleep 2
done

echo "[argocd] Apply odoo-staging Application..."
export DOCKER_GID
envsubst '${DOCKER_GID}' < "$APP_TEMPLATE" | kubectl apply -f -

ADMIN_PASS="$(kubectl -n "$ARGO_NAMESPACE" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"

echo ""
echo "[argocd] Ready."
kubectl -n "$ARGO_NAMESPACE" get pods
echo ""
echo "Argo CD UI (from laptop):"
echo "  ssh -i ~/.ssh/azure_vm_key -L 8081:127.0.0.1:8081 azureuser@<VM_IP> \\"
echo "    'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl -n ${ARGO_NAMESPACE} port-forward svc/${ARGO_RELEASE}-server 8081:80'"
echo "  Open http://127.0.0.1:8081"
echo "  Login: admin / ${ADMIN_PASS:-<run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d>}"
echo ""
echo "Next: Argo UI → Applications → odoo-staging → Sync (manual first time)."
echo "If repo is private, re-run with: ARGOCD_GITHUB_TOKEN=<pat> ./scripts/install-argocd.sh"
