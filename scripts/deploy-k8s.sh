#!/usr/bin/env bash
# Deploy prod + staging Odoo on k3s via Helm.
# Prod DB = Azure Postgres. Staging DB = postgres:16 pod on VM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${REPO_DIR}/.env"
CHART="${REPO_DIR}/helm/odoo"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

if ! command -v helm >/dev/null; then
  echo "helm not found — run ./scripts/install-k3s.sh first (installs Helm too)" >&2
  exit 1
fi

STAGING_USER="${STAGING_DB_USER:-odoo}"
STAGING_PASSWORD="${STAGING_DB_PASSWORD:-odoo-staging-change-me}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

: "${DB_HOST:?Set DB_HOST in .env}"
: "${DB_USER:?Set DB_USER in .env}"
: "${DB_PASSWORD:?Set DB_PASSWORD in .env}"

echo "[k8s] Namespace..."
kubectl create namespace odoo --dry-run=client -o yaml | kubectl apply -f -

echo "[k8s] Staging Postgres (on VM, not Azure)..."
kubectl -n odoo create secret generic postgres-staging \
  --from-literal=POSTGRES_USER="$STAGING_USER" \
  --from-literal=POSTGRES_PASSWORD="$STAGING_PASSWORD" \
  --from-literal=POSTGRES_DB=odoo_staging \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${REPO_DIR}/k8s/postgres-staging.yaml"
kubectl -n odoo wait --for=condition=Available deployment/postgres-staging --timeout=180s

echo "[k8s] Prod DB secret (Azure Postgres)..."
kubectl -n odoo create secret generic odoo-db \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[k8s] Staging Odoo DB secret (VM postgres)..."
kubectl -n odoo create secret generic odoo-staging-db \
  --from-literal=DB_HOST=postgres-staging \
  --from-literal=DB_USER="$STAGING_USER" \
  --from-literal=DB_PASSWORD="$STAGING_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "${GHCR_TOKEN:-}" ]]; then
  kubectl -n odoo create secret docker-registry ghcr-pull \
    --docker-server=ghcr.io \
    --docker-username=CS-Usman \
    --docker-password="$GHCR_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

HELM_EXTRA=()
if kubectl -n odoo get secret ghcr-pull >/dev/null 2>&1; then
  HELM_EXTRA=(-f "${CHART}/values-ghcr-pull.yaml")
fi

IMAGE_TAG="${IMAGE_TAG:-latest}"
HELM_SET=(--set "image.tag=${IMAGE_TAG}")

echo "[k8s] Image tag: ${IMAGE_TAG}"

# Compose is retired after k3s cutover — keep it stopped if present.
if [[ -f "${REPO_DIR}/docker-compose.azure.yml" ]]; then
  sudo docker compose -f "${REPO_DIR}/docker-compose.azure.yml" stop 2>/dev/null || true
fi

echo "[k8s] Helm odoo-prod (Azure DB)..."
helm upgrade --install odoo-prod "$CHART" \
  -n odoo \
  -f "${CHART}/values-prod.yaml" \
  "${HELM_EXTRA[@]}" \
  "${HELM_SET[@]}"

echo "[k8s] Helm odoo-staging (VM postgres)..."
helm upgrade --install odoo-staging "$CHART" \
  -n odoo \
  -f "${CHART}/values-staging.yaml" \
  "${HELM_EXTRA[@]}" \
  "${HELM_SET[@]}"

kubectl -n odoo rollout status deployment/odoo-prod --timeout=180s
kubectl -n odoo rollout status deployment/odoo-staging --timeout=180s
kubectl -n odoo get pods,svc,ingress

echo ""
echo "Prod:    http://$(curl -sf ifconfig.me 2>/dev/null || echo '<VM_IP>')/  → Azure Postgres"
echo "Staging: http://$(curl -sf ifconfig.me 2>/dev/null || echo '<VM_IP>'):8080/ → VM postgres-staging pod"
echo "Run ./scripts/seed-staging.sh once to copy prod data into staging."
