#!/usr/bin/env bash
# cert-manager + Let's Encrypt ClusterIssuer (HTTP-01 via ingress-nginx).
#
#   export LETSENCRYPT_EMAIL='you@example.com'
#   ./scripts/install-cert-manager.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CM_DIR="${REPO_DIR}/k8s/cert-manager"

: "${KUBECONFIG:?Run az aks get-credentials first}"
: "${LETSENCRYPT_EMAIL:?Set LETSENCRYPT_EMAIL for Lets Encrypt account}"

if ! command -v helm >/dev/null; then
  echo "[cert-manager] helm not found" >&2
  exit 1
fi

echo "[cert-manager] Install cert-manager..."
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update jetstack
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set installCRDs=true \
  --set prometheus.enabled=false \
  --wait --timeout 10m

echo "[cert-manager] Wait for controller..."
kubectl -n cert-manager rollout status deployment/cert-manager --timeout=300s
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=300s

deadline=$((SECONDS + 120))
until kubectl get crd clusterissuers.cert-manager.io certificates.cert-manager.io >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "[cert-manager] Timed out waiting for CRDs" >&2
    exit 1
  fi
  sleep 2
done

export LETSENCRYPT_EMAIL
envsubst '${LETSENCRYPT_EMAIL}' <"${CM_DIR}/cluster-issuer-letsencrypt-prod.yaml.tpl" | kubectl apply -f -

echo "[cert-manager] ClusterIssuer letsencrypt-prod ready."
echo "Enable TLS on Odoo Ingress: ingress.certManager.clusterIssuer + host in Helm values."
