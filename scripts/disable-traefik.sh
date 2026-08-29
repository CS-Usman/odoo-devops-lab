#!/usr/bin/env bash
# Disable k3s Traefik — Odoo pods bind hostPort :80 (prod) and :8080 (staging) directly.
# Traefik ServiceLB often does not bind :80 on single-node Azure VMs.

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

echo "[k3s] Disable Traefik (Odoo uses hostPort instead)..."

sudo rm -f /var/lib/rancher/k3s/server/manifests/traefik-odoo-config.yaml
kubectl delete helmchartconfig traefik -n kube-system --ignore-not-found 2>/dev/null || true

# Stop Traefik and ServiceLB immediately so :80 is free for odoo-prod.
kubectl -n kube-system scale deployment traefik --replicas=0 2>/dev/null || true
while IFS= read -r ds; do
  [[ -n "$ds" ]] && kubectl -n kube-system delete "$ds" --ignore-not-found
done < <(kubectl -n kube-system get ds -o name 2>/dev/null | grep svclb-traefik || true)

# Persist disable across k3s restarts/upgrades.
if [[ ! -f /etc/rancher/k3s/config.yaml ]] || ! grep -q 'traefik' /etc/rancher/k3s/config.yaml 2>/dev/null; then
  echo "[k3s] Write /etc/rancher/k3s/config.yaml (disable traefik)..."
  sudo mkdir -p /etc/rancher/k3s
  if [[ -f /etc/rancher/k3s/config.yaml ]]; then
    sudo tee -a /etc/rancher/k3s/config.yaml >/dev/null <<'EOF'
disable:
  - traefik
EOF
  else
    echo 'write-kubeconfig-mode: "644"
disable:
  - traefik' | sudo tee /etc/rancher/k3s/config.yaml >/dev/null
  fi
fi

echo "[k3s] Traefik scaled down — port 80 free for odoo-prod hostPort"
