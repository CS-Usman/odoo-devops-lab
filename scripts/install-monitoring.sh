#!/usr/bin/env bash
# Install Prometheus + Grafana (kube-prometheus-stack) for Phase 7 Session A.
# Run on VM after k3s is up: ./scripts/install-monitoring.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
VALUES_FILE="${REPO_DIR}/helm/monitoring/values.yaml"
MONITORING_DIR="${REPO_DIR}/k8s/monitoring"

MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
MONITORING_RELEASE="${MONITORING_RELEASE:-monitoring}"
GRAFANA_NODE_PORT="${GRAFANA_NODE_PORT:-30300}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-odoo-lab-change-me}"

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

if ! command -v helm >/dev/null; then
  echo "[monitoring] helm not found — run ./scripts/install-k3s.sh first" >&2
  exit 1
fi

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "[monitoring] Missing ${VALUES_FILE}" >&2
  exit 1
fi

echo "[monitoring] Add prometheus-community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community

echo "[monitoring] Install kube-prometheus-stack (release=${MONITORING_RELEASE})..."
helm upgrade --install "$MONITORING_RELEASE" prometheus-community/kube-prometheus-stack \
  -n "$MONITORING_NAMESPACE" \
  --create-namespace \
  -f "$VALUES_FILE" \
  --set "grafana.adminPassword=${GRAFANA_ADMIN_PASSWORD}" \
  --wait \
  --timeout 15m

echo "[monitoring] Wait for core workloads..."
kubectl -n "$MONITORING_NAMESPACE" rollout status "deployment/${MONITORING_RELEASE}-operator" --timeout=300s
kubectl -n "$MONITORING_NAMESPACE" rollout status "deployment/${MONITORING_RELEASE}-grafana" --timeout=300s
kubectl -n "$MONITORING_NAMESPACE" rollout status "daemonset/${MONITORING_RELEASE}-node-exporter" --timeout=300s

echo "[monitoring] Wait for Prometheus CR..."
deadline=$((SECONDS + 180))
until kubectl -n "$MONITORING_NAMESPACE" get prometheus "${MONITORING_RELEASE}-prometheus" >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "[monitoring] Timed out waiting for Prometheus CR" >&2
    exit 1
  fi
  sleep 3
done

kubectl -n "$MONITORING_NAMESPACE" wait --for=condition=Ready \
  "prometheus/${MONITORING_RELEASE}-prometheus" --timeout=300s

echo "[monitoring] Apply Odoo health probes..."
kubectl apply -f "${MONITORING_DIR}/probe-odoo-health.yaml"

NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
PUBLIC_IP="$(curl -sf --max-time 5 ifconfig.me 2>/dev/null || true)"

echo ""
echo "[monitoring] Ready."
kubectl -n "$MONITORING_NAMESPACE" get pods
echo ""
echo "Grafana:"
echo "  URL (NodePort): http://${NODE_IP}:${GRAFANA_NODE_PORT}"
if [[ -n "$PUBLIC_IP" ]]; then
  echo "  URL (public):   http://${PUBLIC_IP}:${GRAFANA_NODE_PORT}  (open NSG port ${GRAFANA_NODE_PORT} if blocked)"
fi
echo "  User: admin"
echo "  Pass: ${GRAFANA_ADMIN_PASSWORD}  (override with GRAFANA_ADMIN_PASSWORD=...)"
echo ""
echo "Prometheus UI (cluster only):"
echo "  kubectl -n ${MONITORING_NAMESPACE} port-forward svc/prometheus-${MONITORING_RELEASE}-prometheus 9090:9090"
echo ""
echo "Next: Session B — Odoo dashboards; Session C — Loki logs."
