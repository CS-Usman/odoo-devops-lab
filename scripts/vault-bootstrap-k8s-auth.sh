#!/usr/bin/env bash
# Bootstrap Vault Kubernetes auth for AKS + External Secrets Operator.
#
# Run once when Vault and the cluster are both available:
#   - Vault initialized and unsealed
#   - kubectl configured (az aks get-credentials)
#   - KV v2 at secret/ and odoo paths seeded
#
# Prerequisites:
#   export VAULT_ADDR='https://vault.example.com:8200'
#   export VAULT_CACERT='/path/to/ca.crt'
#   export VAULT_TOKEN='<admin-token>'
#
# Usage:
#   ./scripts/vault-bootstrap-k8s-auth.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
POLICY_FILE="${REPO_DIR}/k8s/vault/policy-odoo-read.hcl"
RBAC_FILE="${REPO_DIR}/k8s/vault/vault-auth-rbac.yaml"

: "${KUBECONFIG:?Set KUBECONFIG or run az aks get-credentials first}"
export VAULT_ADDR="${VAULT_ADDR:?Set VAULT_ADDR}"
export VAULT_CACERT="${VAULT_CACERT:-}"

VAULT_AUTH_SA="${VAULT_AUTH_SA:-vault-auth}"
VAULT_AUTH_NS="${VAULT_AUTH_NS:-kube-system}"
ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
ESO_SA="${ESO_SA:-external-secrets}"
VAULT_K8S_ROLE="${VAULT_K8S_ROLE:-external-secrets}"
VAULT_POLICY="${VAULT_POLICY:-odoo-read}"
TOKEN_DURATION="${TOKEN_DURATION:-87600h}"

K8S_API_HOST="${K8S_API_HOST:-$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')}"
: "${K8S_API_HOST:?Could not detect Kubernetes API URL — set K8S_API_HOST}"

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

prepare_cluster_ca_cert() {
  TMP_CA="$(mktemp)"
  if ! kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
    | base64 -d >"$TMP_CA"; then
    echo "[vault] Failed to extract cluster CA from kubeconfig" >&2
    exit 1
  fi
  if [[ ! -s "$TMP_CA" ]]; then
    echo "[vault] Cluster CA from kubeconfig is empty" >&2
    exit 1
  fi
  echo "$TMP_CA"
}

echo "[vault] Preflight..."
require_cmd vault
require_cmd kubectl
require_cmd base64
require_file "$POLICY_FILE"
require_file "$RBAC_FILE"

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  echo "[vault] Set VAULT_TOKEN before running." >&2
  exit 1
fi

if ! vault status >/dev/null 2>&1; then
  echo "[vault] Cannot reach Vault at ${VAULT_ADDR}. Is it unsealed?" >&2
  vault status >&2 || true
  exit 1
fi

if vault status -format=json | grep -q '"sealed":true'; then
  echo "[vault] Vault is sealed — unseal first." >&2
  exit 1
fi

CLUSTER_CA="$(prepare_cluster_ca_cert)"

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

echo "[vault] Configure kubernetes auth (API ${K8S_API_HOST})..."
vault write auth/kubernetes/config \
  token_reviewer_jwt="$REVIEWER_JWT" \
  kubernetes_host="$K8S_API_HOST" \
  kubernetes_ca_cert=@"$CLUSTER_CA"

echo "[vault] Write policy ${VAULT_POLICY}..."
vault policy write "$VAULT_POLICY" "$POLICY_FILE"

echo "[vault] Create role ${VAULT_K8S_ROLE} for External Secrets (${ESO_NAMESPACE}/${ESO_SA})..."
vault write "auth/kubernetes/role/${VAULT_K8S_ROLE}" \
  bound_service_account_names="$ESO_SA" \
  bound_service_account_namespaces="$ESO_NAMESPACE" \
  policies="$VAULT_POLICY" \
  ttl=24h

echo ""
echo "[vault] Kubernetes auth bootstrap complete."
echo ""
echo "Verify:"
echo "  vault read auth/kubernetes/config"
echo "  vault policy read ${VAULT_POLICY}"
echo "  vault read auth/kubernetes/role/${VAULT_K8S_ROLE}"
echo ""
echo "Next:"
echo "  1. ./scripts/vault-seed-secrets.sh   (if not done)"
echo "  2. ./scripts/install-external-secrets.sh"
echo "  3. Or ./scripts/seed-aks-db-secret.sh for bootstrap without Vault"
