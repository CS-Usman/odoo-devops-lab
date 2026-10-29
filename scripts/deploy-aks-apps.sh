#!/usr/bin/env bash
# Helm deploy on AKS (manual / bootstrap path; GitOps uses Argo CD).
#
# Order: postgres-staging → pgbouncer → odoo-prod → odoo-staging
#
# Requires secrets from ./scripts/seed-aks-db-secret.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_kubeconfig
NS="$(odoo_namespace)"

if ! kubectl -n "$NS" get secret odoo-db >/dev/null 2>&1; then
  echo "[aks] Missing secret odoo-db — run ./scripts/seed-aks-db-secret.sh" >&2
  exit 1
fi

IMAGE_TAG="${IMAGE_TAG:-$(grep 'tag:' "${REPO_DIR}/helm/odoo/environments/production/image-tag.yaml" | awk '{print $2}' | tr -d '"')}"

HELM_GHCR=()
if kubectl -n "$NS" get secret ghcr-pull >/dev/null 2>&1; then
  HELM_GHCR=(-f "${REPO_DIR}/helm/odoo/values-ghcr-pull.yaml")
fi

if kubectl -n "$NS" get secret postgres-staging-auth >/dev/null 2>&1; then
  echo "[aks] Helm upgrade postgres-staging (in-cluster DB)..."
  helm upgrade --install postgres-staging "${REPO_DIR}/helm/postgres-staging" \
    -n "$NS" \
    -f "${REPO_DIR}/helm/postgres-staging/values.yaml" \
    --wait --timeout 10m
  wait_postgres_staging || true
else
  echo "[aks] Skip postgres-staging (no secret postgres-staging-auth)." >&2
fi

echo "[aks] Helm upgrade pgbouncer (production → Azure Postgres)..."
helm upgrade --install pgbouncer "${REPO_DIR}/helm/pgbouncer" \
  -n "$NS" \
  -f "${REPO_DIR}/helm/pgbouncer/values.yaml" \
  --set fullnameOverride=pgbouncer \
  --wait --timeout 5m

echo "[aks] Helm upgrade odoo-prod..."
helm upgrade --install odoo-prod "${REPO_DIR}/helm/odoo" \
  -n "$NS" \
  -f "${REPO_DIR}/helm/odoo/values-prod.yaml" \
  -f "${REPO_DIR}/helm/odoo/environments/production/values.yaml" \
  -f "${REPO_DIR}/helm/odoo/environments/production/image-tag.yaml" \
  "${HELM_GHCR[@]}" \
  --set "image.tag=${IMAGE_TAG}" \
  --wait --timeout 15m

if kubectl -n "$NS" get secret odoo-staging-db >/dev/null 2>&1; then
  echo "[aks] Helm upgrade odoo-staging..."
  helm upgrade --install odoo-staging "${REPO_DIR}/helm/odoo" \
    -n "$NS" \
    -f "${REPO_DIR}/helm/odoo/values-staging.yaml" \
    -f "${REPO_DIR}/helm/odoo/environments/production/image-tag.yaml" \
    "${HELM_GHCR[@]}" \
    --set "image.tag=${IMAGE_TAG}" \
    --wait --timeout 15m
else
  echo "[aks] Skip odoo-staging (no secret odoo-staging-db)." >&2
fi

kubectl -n "$NS" get pods,svc,pvc
echo "[aks] After first deploy: ./scripts/refresh-staging-from-prod.sh"
