#!/usr/bin/env bash
# External Secrets Operator + Azure Key Vault (workload identity). Preferred secrets path for this lab.
#
#   terraform apply
#   ./scripts/seed-keyvault-secrets.sh
#   ./scripts/install-external-secrets-azure.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ESO_DIR="${REPO_DIR}/k8s/external-secrets"

ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
ESO_RELEASE="${ESO_RELEASE:-external-secrets}"
ESO_SERVICE_ACCOUNT="${ESO_SERVICE_ACCOUNT:-external-secrets}"

: "${KUBECONFIG:?Run az aks get-credentials first}"

if ! command -v helm >/dev/null; then
  echo "[eso-azure] helm not found" >&2
  exit 1
fi

KEY_VAULT_URI="${KEY_VAULT_URI:-}"
CLIENT_ID="${ESO_MANAGED_IDENTITY_CLIENT_ID:-}"
if [[ -d "${REPO_DIR}/terraform" ]]; then
  [[ -z "$KEY_VAULT_URI" ]] && KEY_VAULT_URI="$(terraform -chdir="${REPO_DIR}/terraform" output -raw key_vault_uri 2>/dev/null || true)"
  [[ -z "$CLIENT_ID" ]] && CLIENT_ID="$(terraform -chdir="${REPO_DIR}/terraform" output -raw eso_managed_identity_client_id 2>/dev/null || true)"
fi

: "${KEY_VAULT_URI:?Set KEY_VAULT_URI or terraform output key_vault_uri}"
: "${CLIENT_ID:?Set ESO_MANAGED_IDENTITY_CLIENT_ID or terraform output eso_managed_identity_client_id}"

echo "[eso-azure] Install External Secrets Operator (workload identity)..."
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets

kubectl create namespace "$ESO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESO_NAMESPACE" azure-workload-identity-use=true --overwrite

helm upgrade --install "$ESO_RELEASE" external-secrets/external-secrets \
  -n "$ESO_NAMESPACE" \
  --set installCRDs=true \
  --set serviceAccount.name="$ESO_SERVICE_ACCOUNT" \
  --set-string "serviceAccount.annotations.azure\.workload\.identity/client-id=${CLIENT_ID}" \
  --wait \
  --timeout 10m

kubectl -n "$ESO_NAMESPACE" rollout status "deployment/${ESO_RELEASE}" --timeout=300s

deadline=$((SECONDS + 120))
until kubectl get crd clustersecretstores.external-secrets.io externalsecrets.external-secrets.io >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "[eso-azure] Timed out waiting for CRDs" >&2
    exit 1
  fi
  sleep 2
done

AZURE_TENANT_ID="${AZURE_TENANT_ID:-$(az account show --query tenantId -o tsv 2>/dev/null || true)}"
: "${AZURE_TENANT_ID:?az login required for AZURE_TENANT_ID}"

export KEY_VAULT_URI ESO_NAMESPACE ESO_SERVICE_ACCOUNT AZURE_TENANT_ID
envsubst '${KEY_VAULT_URI} ${ESO_NAMESPACE} ${ESO_SERVICE_ACCOUNT} ${AZURE_TENANT_ID}' \
  <"${ESO_DIR}/cluster-secret-store-azurekv.yaml.tpl" | kubectl apply -f -

kubectl create namespace odoo --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${ESO_DIR}/externalsecret-odoo-db-azurekv.yaml"
kubectl apply -f "${ESO_DIR}/externalsecret-odoo-staging-db-azurekv.yaml"
kubectl apply -f "${ESO_DIR}/externalsecret-postgres-staging-auth-azurekv.yaml"

echo "[eso-azure] Waiting for synced secrets..."
deadline=$((SECONDS + 180))
until kubectl -n odoo get secret odoo-db odoo-staging-db postgres-staging-auth >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    kubectl -n odoo get externalsecret >&2 || true
    exit 1
  fi
  sleep 5
done

echo "[eso-azure] Ready."
kubectl -n odoo get externalsecret,secret | grep -E 'odoo|postgres-staging|NAME' || true
