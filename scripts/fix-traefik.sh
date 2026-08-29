#!/usr/bin/env bash
# Recover k3s Traefik when nothing listens on :80 (Connection refused).
# Run on VM: ./scripts/fix-traefik.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

echo "[traefik] Install HelmChartConfig into k3s manifests dir..."
sudo mkdir -p /var/lib/rancher/k3s/server/manifests
sudo cp "${REPO_DIR}/k8s/traefik-helmchartconfig.yaml" \
  /var/lib/rancher/k3s/server/manifests/traefik-odoo-config.yaml
kubectl apply -f "${REPO_DIR}/k8s/traefik-helmchartconfig.yaml"

if [[ -f /var/lib/rancher/k3s/server/manifests/traefik.yaml.skip ]]; then
  echo "[traefik] ERROR: Traefik is disabled (traefik.yaml.skip)." >&2
  echo "  sudo rm /var/lib/rancher/k3s/server/manifests/traefik.yaml.skip" >&2
  echo "  sudo systemctl restart k3s" >&2
  exit 1
fi

if grep -q 'disable=traefik' /etc/systemd/system/k3s.service 2>/dev/null; then
  echo "[traefik] ERROR: k3s was started with --disable=traefik." >&2
  exit 1
fi

ready="$(kubectl -n kube-system get helmchart traefik \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")"

if [[ "$ready" != "True" ]]; then
  echo "[traefik] HelmChart not Ready (status=${ready:-missing}) — restart k3s to reconcile..."
  kubectl -n kube-system get helmchart traefik -o wide 2>/dev/null || true
  kubectl -n kube-system describe helmchart traefik 2>/dev/null | tail -25 || true
  sudo systemctl restart k3s
  echo "[traefik] Wait for k3s node..."
  sleep 15
  kubectl wait --for=condition=Ready node --all --timeout=180s
fi

echo "[traefik] Wait for Traefik + ServiceLB pods..."
deadline=$((SECONDS + 300))
while (( SECONDS < deadline )); do
  if ss -tln | grep -q ':80 '; then
    break
  fi
  kubectl -n kube-system get pods 2>/dev/null | grep -Ei 'traefik|svclb' || true
  sleep 5
done

if ! ss -tln | grep -q ':80 '; then
  echo "[traefik] FAILED — still nothing on :80" >&2
  kubectl -n kube-system get pods -o wide | grep -Ei 'traefik|svclb|NAME' >&2 || true
  kubectl -n kube-system describe helmchart traefik 2>&1 | tail -30 >&2 || true
  exit 1
fi

echo "[traefik] OK — port 80 listening"
ss -tln | grep -E ':80|:8080' || true
echo ""
echo "Next: ./scripts/deploy-k8s.sh"
