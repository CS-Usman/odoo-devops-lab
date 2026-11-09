#!/usr/bin/env bash
# Install ingress-nginx (LoadBalancer) or confirm Argo CD app ingress-nginx is healthy.
# Prints a lab-friendly *.sslip.io host name from the Azure LB IP.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"

if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
  echo "[ingress] Applying Argo-style install via Helm..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update ingress-nginx
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    -n "$NAMESPACE" --create-namespace \
    --set controller.ingressClassResource.default=true \
    --set controller.service.type=LoadBalancer \
    --wait --timeout 10m
fi

echo "[ingress] Waiting for LoadBalancer IP..."
deadline=$((SECONDS + 300))
IP=""
while (( SECONDS < deadline )); do
  IP="$(kubectl -n "$NAMESPACE" get svc ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [[ -n "$IP" ]] && break
  sleep 5
done

if [[ -z "$IP" ]]; then
  echo "[ingress] No external IP yet — check: kubectl -n ${NAMESPACE} get svc" >&2
  exit 1
fi

HOST="${IP//./-}.sslip.io"

echo ""
echo "[ingress] LoadBalancer IP: ${IP}"
echo "[ingress] Lab host (no DNS purchase): https?://${HOST}  (use http unless you add TLS)"
echo ""
echo "Enable Odoo ingress in git:"
echo "  helm/odoo/environments/production/ingress.yaml  → ingress.enabled: true, host: ${HOST}"
echo "  helm/odoo/environments/staging/ingress.yaml   → staging host e.g. staging-${HOST}"
echo ""
echo "Full guide: docs/aks/INGRESS.md"
echo "Smoke test:  SMOKE_URL=http://${HOST} ./scripts/smoke-test.sh"
