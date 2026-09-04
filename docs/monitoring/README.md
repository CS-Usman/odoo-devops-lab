# Phase 7 — Monitoring

**Status:** Session A done · Session B (Odoo dashboard) in repo.

## Architecture

```text
k3s namespace: monitoring
├── Prometheus          metrics store (3-day retention)
├── Grafana             dashboards (NodePort :30300)
├── node-exporter       VM CPU/RAM/disk
├── kube-state-metrics  pod status
└── blackbox-exporter   Odoo /devops/health probes
```

## Install / upgrade (VM)

```bash
cd ~/odoo-devops-lab && git pull
chmod +x scripts/install-monitoring.sh
./scripts/install-monitoring.sh
```

Or after pulling Session B changes only:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f helm/monitoring/values.yaml \
  --set grafana.adminPassword=odoo-lab-change-me --wait --timeout 10m
kubectl -n monitoring create configmap grafana-dashboard-odoo-lab \
  --from-file=odoo-lab-overview.json=helm/monitoring/dashboards/odoo-lab-overview.json \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring label configmap grafana-dashboard-odoo-lab grafana_dashboard=1 --overwrite
```

## Access Grafana (SSH tunnel from laptop)

```bash
ssh -i ~/.ssh/azure_vm_key -L 3000:127.0.0.1:3000 azureuser@<VM_IP> \
  'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80'
```

Open **http://127.0.0.1:3000** — login `admin` / `odoo-lab-change-me`.

Public (if NSG allows **30300**): `http://<VM_IP>:30300`

## Session B — Odoo DevOps Lab dashboard

Auto-loaded from git (no grafana.com import):

**Dashboards → Odoo DevOps Lab**

| Panel | Metric |
|-------|--------|
| Odoo /devops/health | `probe_success` (prod + staging) |
| VM CPU / Memory / Disk | node-exporter |
| Odoo pods ready | `kube_pod_container_status_ready{namespace="odoo"}` |

Manual upload (alternative): **Import → Upload JSON** → `helm/monitoring/dashboards/odoo-lab-overview.json`

## Prometheus datasource

Provisioned in `helm/monitoring/values.yaml`. If missing:

**Connections → Data sources → Prometheus** → URL `http://monitoring-prometheus.monitoring.svc:9090`

## Files

| Path | Purpose |
|------|---------|
| `helm/monitoring/values.yaml` | Stack limits, Grafana datasource, dashboard sidecar |
| `helm/monitoring/dashboards/odoo-lab-overview.json` | Session B dashboard |
| `helm/monitoring/blackbox-values.yaml` | Odoo health probes |
| `scripts/install-monitoring.sh` | Full install |

## Sessions roadmap

| Session | Topic | Status |
|---------|--------|--------|
| A | Prometheus + Grafana core | Done |
| B | Odoo DevOps Lab dashboard | Done |
| C | Loki + Promtail logs | — |
| D | Alertmanager rules | — |
| E | Nginx access + mark Phase 7 done | — |
