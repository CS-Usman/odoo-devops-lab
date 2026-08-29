#!/usr/bin/env bash
# Install k3s on the Azure VM and configure Traefik for :80 + :8080.
# Run on VM: curl -sfL ... | bash   OR   ./scripts/install-k3s.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

if ! command -v curl >/dev/null; then
  sudo apt-get update && sudo apt-get install -y curl
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if ! command -v k3s >/dev/null; then
  echo "[k3s] Install k3s..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
else
  echo "[k3s] k3s already installed — skipping install"
fi

echo "[k3s] Wait for node..."
deadline=$((SECONDS + 120))
until kubectl get nodes -o name 2>/dev/null | grep -q .; do
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for k3s node to register" >&2
    exit 1
  fi
  sleep 2
done
kubectl wait --for=condition=Ready node --all --timeout=120s

echo "[k3s] Configure Traefik (:80 prod, :8080 staging)..."
kubectl apply -f "${REPO_DIR}/k8s/traefik-helmchartconfig.yaml"

echo "[k3s] Disable host Nginx (Traefik takes :80)..."
if systemctl is-active nginx >/dev/null 2>&1; then
  sudo systemctl stop nginx
  sudo systemctl disable nginx
fi

echo "[k3s] Install Helm..."
if ! command -v helm >/dev/null; then
  curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "[k3s] Ready. kubectl get nodes:"
kubectl get nodes
echo ""
echo "Next: ./scripts/migrate-compose-to-k8s.sh && ./scripts/deploy-k8s.sh"
