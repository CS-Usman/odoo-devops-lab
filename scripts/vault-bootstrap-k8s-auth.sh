#!/usr/bin/env bash
# Bootstrap Vault Kubernetes auth for k3s + External Secrets Operator.
#
# Run ONCE on the Azure VM after:
#   - Vault is installed, initialized, and unsealed
#   - k3s is running
#   - KV v2 enabled at secret/ and odoo secrets seeded (vault kv put secret/odoo/...)
#
# Prerequisites:
#   export VAULT_ADDR='https://127.0.0.1:8200'
#   export VAULT_CACERT='/opt/vault/tls/tls.crt'
#   export VAULT_TOKEN='<root-or-admin-token>'
#
# Usage:
#   cd ~/odoo-devops-lab && ./scripts/vault-bootstrap-k8s-auth.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
POLICY_FILE="${REPO_DIR}/k8s/vault/policy-odoo-read.hcl"
RBAC_FILE="${REPO_DIR}/k8s/vault/vault-auth-rbac.yaml"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
export VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
export VAULT_CACERT="${VAULT_CACERT:-/opt/vault/tls/tls.crt}"

VAULT_AUTH_SA="${VAULT_AUTH_SA:-vault-auth}"
VAULT_AUTH_NS="${VAULT_AUTH_NS:-kube-system}"
K8S_API_HOST="${K8S_API_HOST:-https://127.0.0.1:6443}"
K3S_CA_CERT="${K3S_CA_CERT:-/var/lib/rancher/k3s/server/tls/server-ca.crt}"
ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
ESO_SA="${ESO_SA:-external-secrets}"
VAULT_K8S_ROLE="${VAULT_K8S_ROLE:-external-secrets}"
VAULT_POLICY="${VAULT_POLICY:-odoo-read}"
TOKEN_DURATION="${TOKEN_DURATION:-87600h}"

TMP_CA=""
cleanup() {
  if [[ -n "$TMP_CA" && -f "$TMP_CA" ]]; then
    rm -f "$TMP_CA"
  fi
}
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null; then
    echo "[vault] Missing command: $1" >&2
    exit 1
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "[vault] Missing file: $1" >&2
    exit 1
  fi
}

# k3s CA on disk is root-only; fall back to kubeconfig CA (works for azureuser).
prepare_k3s_ca_cert() {
  if [[ -r "$K3S_CA_CERT" ]]; then
    echo "$K3S_CA_CERT"
    return 0
  fi
  if [[ -f "$K3S_CA_CERT" ]] && sudo test -r "$K3S_CA_CERT" 2>/dev/null; then
    TMP_CA="$(mktemp)"
    sudo cat "$K3S_CA_CERT" >"$TMP_CA"
    echo "$TMP_CA"
    return 0
  fi
  TMP_CA="$(mktemp)"
  if ! kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d >"$TMP_CA"; then
    echo "[vault] Failed to extract k3s CA from kubeconfig" >&2
    exit 1
  fi
  if [[ ! -s "$TMP_CA" ]]; then
    echo "[vault] k3s CA cert from kubeconfig is empty" >&2
    exit 1
  fi
  echo "[vault] Using k3s CA from kubeconfig (${K3S_CA_CERT} not readable)" >&2
  echo "$TMP_CA"
}

echo "[vault] Preflight..."
require_cmd vault
require_cmd kubectl
require_cmd base64
require_file "$POLICY_FILE"
require_file "$RBAC_FILE"

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  echo "[vault] Set VAULT_TOKEN (root or policy-admin token) before running." >&2
  exit 1
fi

if ! vault status >/dev/null 2>&1; then
  echo "[vault] Cannot reach Vault at ${VAULT_ADDR}. Is it unsealed?" >&2
  vault status >&2 || true
  exit 1
fi

if vault status -format=json | grep -q '"sealed":true'; then
  echo "[vault] Vault is sealed — run: vault operator unseal" >&2
  exit 1
fi

K3S_CA_USE="$(prepare_k3s_ca_cert)"

echo "[vault] Apply Kubernetes token reviewer RBAC..."
kubectl apply -f "$RBAC_FILE"
kubectl -n "$VAULT_AUTH_NS" get sa "$VAULT_AUTH_SA" >/dev/null

echo "[vault] Create token reviewer JWT for ${VAULT_AUTH_SA}..."
REVIEWER_JWT="$(kubectl -n "$VAULT_AUTH_NS" create token "$VAULT_AUTH_SA" --duration="$TOKEN_DURATION")"

if [[ -z "$REVIEWER_JWT" ]]; then
  echo "[vault] Failed to create reviewer token for ${VAULT_AUTH_SA}" >&2
  exit 1
fi

echo "[vault] Enable kubernetes auth (if needed)..."
if ! vault auth list -format=json | grep -q '"kubernetes/"'; then
  vault auth enable kubernetes
else
  echo "[vault] kubernetes auth already enabled"
fi

echo "[vault] Configure kubernetes auth (k3s API ${K8S_API_HOST})..."
vault write auth/kubernetes/config \
  token_reviewer_jwt="$REVIEWER_JWT" \
  kubernetes_host="$K8S_API_HOST" \
  kubernetes_ca_cert=@"$K3S_CA_USE"

echo "[vault] Write policy ${VAULT_POLICY}..."
vault policy write "$VAULT_POLICY" "$POLICY_FILE"

echo "[vault] Create role ${VAULT_K8S_ROLE} for External Secrets (${ESO_NAMESPACE}/${ESO_SA})..."
vault write "auth/kubernetes/role/${VAULT_K8S_ROLE}" \
  bound_service_account_names="$ESO_SA" \
  bound_service_account_namespaces="$ESO_NAMESPACE" \
  policies="$VAULT_POLICY" \
  ttl=24h

NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"

echo ""
echo "[vault] Kubernetes auth bootstrap complete."
echo ""
echo "Verify:"
echo "  vault read auth/kubernetes/config"
echo "  vault policy read ${VAULT_POLICY}"
echo "  vault read auth/kubernetes/role/${VAULT_K8S_ROLE}"
echo ""
echo "External Secrets will use Vault at:"
echo "  https://${NODE_IP}:8200"
echo "  (or https://127.0.0.1:8200 from the VM host)"
echo ""
echo "Next:"
echo "  1. helm upgrade --install external-secrets ...  (see docs/vault/README.md when added)"
echo "  2. kubectl apply -f k8s/external-secrets/"
echo "  3. Remove secret literals from deploy-k8s.sh once ESO syncs odoo-db"
