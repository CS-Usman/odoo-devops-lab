#!/usr/bin/env bash
# Install Prometheus + Grafana (kube-prometheus-stack) for Phase 7.
# Run on VM after k3s is up: ./scripts/install-monitoring.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
VALUES_FILE="${REPO_DIR}/helm/monitoring/values.yaml"
BLACKBOX_VALUES="${REPO_DIR}/helm/monitoring/blackbox-values.yaml"
LOKI_VALUES="${REPO_DIR}/helm/monitoring/loki-values.yaml"
PROMTAIL_VALUES="${REPO_DIR}/helm/monitoring/promtail-values.yaml"
PROMETHEUS_RULES="${REPO_DIR}/helm/monitoring/prometheus-rules-odoo-lab.yaml"
DASHBOARD_JSON="${REPO_DIR}/helm/monitoring/dashboards/odoo-lab-overview.json"

MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
MONITORING_RELEASE="${MONITORING_RELEASE:-monitoring}"
BLACKBOX_RELEASE="${BLACKBOX_RELEASE:-blackbox}"
LOKI_RELEASE="${LOKI_RELEASE:-loki}"
PROMTAIL_RELEASE="${PROMTAIL_RELEASE:-promtail}"
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
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community grafana

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
kubectl -n "$MONITORING_NAMESPACE" rollout status "daemonset/${MONITORING_RELEASE}-prometheus-node-exporter" --timeout=300s

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

if kubectl -n "$MONITORING_NAMESPACE" get alertmanager "${MONITORING_RELEASE}-alertmanager" >/dev/null 2>&1; then
  kubectl -n "$MONITORING_NAMESPACE" wait --for=condition=Ready \
    "alertmanager/${MONITORING_RELEASE}-alertmanager" --timeout=300s
fi

if [[ -f "$PROMETHEUS_RULES" ]]; then
  echo "[monitoring] Apply Odoo lab alert rules (Session D)..."
  kubectl apply -f "$PROMETHEUS_RULES"
fi

if [[ -f "$BLACKBOX_VALUES" ]]; then
  echo "[monitoring] Install blackbox-exporter (Odoo health probes)..."
  helm upgrade --install "$BLACKBOX_RELEASE" prometheus-community/prometheus-blackbox-exporter \
    -n "$MONITORING_NAMESPACE" \
    -f "$BLACKBOX_VALUES" \
    --wait \
    --timeout 5m
fi

if [[ -f "$DASHBOARD_JSON" ]]; then
  echo "[monitoring] Apply Odoo DevOps Lab Grafana dashboard..."
  kubectl -n "$MONITORING_NAMESPACE" create configmap grafana-dashboard-odoo-lab \
    --from-file=odoo-lab-overview.json="$DASHBOARD_JSON" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$MONITORING_NAMESPACE" label configmap grafana-dashboard-odoo-lab \
    grafana_dashboard=1 --overwrite
fi

if [[ -f "$LOKI_VALUES" ]]; then
  echo "[monitoring] Install Loki (logs)..."
  helm upgrade --install "$LOKI_RELEASE" grafana/loki \
    -n "$MONITORING_NAMESPACE" \
    -f "$LOKI_VALUES" \
    --wait \
    --timeout 10m
  kubectl -n "$MONITORING_NAMESPACE" rollout status "statefulset/${LOKI_RELEASE}" --timeout=300s 2>/dev/null \
    || kubectl -n "$MONITORING_NAMESPACE" rollout status "deployment/${LOKI_RELEASE}" --timeout=300s
fi

if [[ -f "$PROMTAIL_VALUES" ]]; then
  echo "[monitoring] Install Promtail (log shipper)..."
  helm upgrade --install "$PROMTAIL_RELEASE" grafana/promtail \
    -n "$MONITORING_NAMESPACE" \
    -f "$PROMTAIL_VALUES" \
    --wait \
    --timeout 10m
  kubectl -n "$MONITORING_NAMESPACE" rollout status "daemonset/${PROMTAIL_RELEASE}" --timeout=300s
fi

echo "[monitoring] Refresh Grafana datasources (Prometheus + Loki)..."
helm upgrade "$MONITORING_RELEASE" prometheus-community/kube-prometheus-stack \
  -n "$MONITORING_NAMESPACE" \
  -f "$VALUES_FILE" \
  --set "grafana.adminPassword=${GRAFANA_ADMIN_PASSWORD}" \
  --wait \
  --timeout 10m

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
echo "  SSH tunnel (from laptop):"
echo "    ssh -i ~/.ssh/azure_vm_key -L 3000:127.0.0.1:3000 azureuser@<VM_IP> \\"
echo "      'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl -n ${MONITORING_NAMESPACE} port-forward svc/${MONITORING_RELEASE}-grafana 3000:80'"
echo ""
echo "Prometheus UI (cluster only):"
echo "  kubectl -n ${MONITORING_NAMESPACE} port-forward svc/${MONITORING_RELEASE}-prometheus 9090:9090"
echo ""
echo "Dashboard: Grafana → Dashboards → Odoo DevOps Lab"
echo "Logs:      Grafana → Explore → Loki → {namespace=\"odoo\"}"
echo ""
echo "Alerts (Session D):"
echo "  Prometheus:    kubectl -n ${MONITORING_NAMESPACE} port-forward svc/${MONITORING_RELEASE}-prometheus 9090:9090"
echo "                 → http://127.0.0.1:9090/alerts"
echo "  Alertmanager:  kubectl -n ${MONITORING_NAMESPACE} port-forward svc/${MONITORING_RELEASE}-alertmanager 9093:9093"
echo "                 → http://127.0.0.1:9093"
echo "Next: Session E — Grafana access + mark Phase 7 done."
