#!/usr/bin/env bash
# Disable k3s Traefik — Nginx uses host :80 → odoo-prod hostPort :8069.
# Must delete the traefik LoadBalancer Service or kube-proxy REJECTs :80 traffic
# (traefik:web has no endpoints).

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

echo "[k3s] Disable Traefik (Nginx + hostPort :8069 for prod)..."

sudo rm -f /var/lib/rancher/k3s/server/manifests/traefik-odoo-config.yaml
kubectl delete helmchartconfig traefik -n kube-system --ignore-not-found 2>/dev/null || true

kubectl -n kube-system scale deployment traefik --replicas=0 2>/dev/null || true
while IFS= read -r ds; do
  [[ -n "$ds" ]] && kubectl -n kube-system delete "$ds" --ignore-not-found
done < <(kubectl -n kube-system get ds -o name 2>/dev/null | grep svclb-traefik || true)

# Critical: orphaned LoadBalancer Service makes kube-proxy REJECT :80 on the node IP.
kubectl -n kube-system delete svc traefik --ignore-not-found 2>/dev/null || true

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

echo "[k3s] Traefik removed — port 80 available for Nginx"
