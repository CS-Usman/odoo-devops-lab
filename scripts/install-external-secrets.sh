#!/usr/bin/env bash
# Install External Secrets Operator and apply Vault-backed ExternalSecrets.
# Run on VM after: vault-bootstrap-k8s-auth.sh + secrets in Vault (secret/odoo/*).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ESO_DIR="${REPO_DIR}/k8s/external-secrets"
VAULT_CA="${VAULT_CA:-/opt/vault/tls/tls.crt}"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

if ! command -v helm >/dev/null; then
  echo "[eso] helm not found — run ./scripts/install-k3s.sh first" >&2
  exit 1
fi

if [[ ! -f "$VAULT_CA" ]]; then
  echo "[eso] Vault CA not found at ${VAULT_CA}" >&2
  exit 1
fi

NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
VAULT_SERVER="${VAULT_SERVER:-https://${NODE_IP}:8200}"

echo "[eso] Install External Secrets Operator..."
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --wait \
  --timeout 10m

echo "[eso] Wait for ESO controller..."
kubectl -n external-secrets wait --for=condition=Available deployment/external-secrets --timeout=300s

echo "[eso] Publish Vault CA to external-secrets namespace..."
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl -n external-secrets create configmap vault-ca \
  --from-file=ca.crt="$VAULT_CA" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[eso] Apply ClusterSecretStore (Vault at ${VAULT_SERVER})..."
export VAULT_SERVER
envsubst '${VAULT_SERVER}' <"${ESO_DIR}/cluster-secret-store.yaml.tpl" | kubectl apply -f -

echo "[eso] Ensure odoo namespace..."
kubectl create namespace odoo --dry-run=client -o yaml | kubectl apply -f -

echo "[eso] Apply ExternalSecrets..."
kubectl apply -f "${ESO_DIR}/externalsecret-odoo-db.yaml"
kubectl apply -f "${ESO_DIR}/externalsecret-odoo-staging-db.yaml"
kubectl apply -f "${ESO_DIR}/externalsecret-postgres-staging.yaml"

echo "[eso] Wait for synced secrets (up to 2 minutes)..."
deadline=$((SECONDS + 120))
until kubectl -n odoo get secret odoo-db odoo-staging-db postgres-staging >/dev/null 2>&1 \
  && [[ "$(kubectl -n odoo get externalsecret odoo-db -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == "True" ]]; do
  if (( SECONDS >= deadline )); then
    echo "[eso] Timed out waiting for ExternalSecrets — debug:" >&2
    kubectl -n odoo get externalsecret >&2 || true
    kubectl -n external-secrets logs deployment/external-secrets --tail=40 >&2 || true
    exit 1
  fi
  sleep 5
done

echo "[eso] Ready."
kubectl -n odoo get externalsecret,secret | grep -E 'odoo-db|odoo-staging-db|postgres-staging|NAME' || true
echo ""
echo "Next: remove kubectl create secret blocks from deploy-k8s.sh once CI deploy verified."
