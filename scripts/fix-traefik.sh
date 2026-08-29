#!/usr/bin/env bash
# Recover k3s Traefik when nothing listens on :80 (Connection refused).
# Uses k3s default Traefik chart — do NOT add custom webstaging ports (breaks chart v40).
# Staging Odoo binds hostPort 8080 directly (see values-staging.yaml).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

echo "[traefik] Remove custom HelmChartConfig (breaks helm-install-traefik on chart v40)..."
sudo rm -f /var/lib/rancher/k3s/server/manifests/traefik-odoo-config.yaml
kubectl delete helmchartconfig traefik -n kube-system --ignore-not-found 2>/dev/null || true

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

if ss -tln | grep -q ':80 '; then
  echo "[traefik] OK — port 80 already listening"
  ss -tln | grep -E ':80|:8080' || true
  exit 0
fi

echo "[traefik] Traefik not on :80 — restart k3s and wait for helm-install-traefik..."
kubectl -n kube-system delete job helm-install-traefik --ignore-not-found 2>/dev/null || true
sudo systemctl restart k3s
sleep 20
kubectl wait --for=condition=Ready node --all --timeout=180s

echo "[traefik] Wait for helm-install-traefik job..."
if ! kubectl -n kube-system wait --for=condition=complete job/helm-install-traefik --timeout=300s 2>/dev/null; then
  echo "[traefik] helm-install-traefik failed — last logs:" >&2
  kubectl -n kube-system logs job/helm-install-traefik --tail=50 2>&1 >&2 || true
  kubectl -n kube-system describe job helm-install-traefik 2>&1 | tail -20 >&2 || true
  exit 1
fi

echo "[traefik] Wait for :80 to bind (ServiceLB)..."
deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
  if ss -tln | grep -q ':80 '; then
    break
  fi
  kubectl -n kube-system get pods 2>/dev/null | grep -Ei 'traefik|svclb' || true
  sleep 3
done

if ! ss -tln | grep -q ':80 '; then
  echo "[traefik] FAILED — still nothing on :80" >&2
  kubectl -n kube-system get pods -o wide | grep -Ei 'traefik|svclb|NAME' >&2 || true
  exit 1
fi

echo "[traefik] OK — port 80 listening (k3s default Traefik)"
ss -tln | grep -E ':80|:8080' || true
echo ""
echo "Next: ./scripts/deploy-k8s.sh"
