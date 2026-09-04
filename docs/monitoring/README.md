# Phase 7 — Monitoring (Session A: Prometheus + Grafana)

**Status: Session A in progress.** Core metrics stack in k3s namespace `monitoring`.

## Architecture (Session A)

```text
k3s namespace: monitoring
├── Prometheus          scrapes metrics, 3-day retention
├── Grafana             dashboards (NodePort :30300)
├── node-exporter       VM CPU/RAM/disk
├── kube-state-metrics  pod/deployment status
└── blackbox-exporter   probes Odoo /devops/health
```

Odoo pods still expose `/devops/health` and `/devops/metrics` — Grafana complements the in-app `devops_server_monitor` dashboard.

## Install (VM, one-time)

```bash
cd ~/odoo-devops-lab
git pull
chmod +x scripts/install-monitoring.sh
./scripts/install-monitoring.sh
```

Optional: set a custom Grafana password before install:

```bash
GRAFANA_ADMIN_PASSWORD='your-password' ./scripts/install-monitoring.sh
```

## Access Grafana

| Method | URL |
|--------|-----|
| On VM | `http://127.0.0.1:30300` |
| From laptop | `http://<VM_PUBLIC_IP>:30300` (add NSG inbound rule for port **30300** if blocked) |

Default login: `admin` / `odoo-lab-change-me` (or your `GRAFANA_ADMIN_PASSWORD`).

## What to check first

1. **Grafana → Dashboards → Kubernetes / Compute Resources / Node** — host CPU and memory.
2. **Grafana → Explore → Prometheus** — query `up` — targets should be `1`.
3. **Prometheus targets** — `odoo-health` probe for prod and staging.

Prometheus UI (not public by default):

```bash
kubectl -n monitoring port-forward svc/prometheus-monitoring-prometheus 9090:9090
# http://127.0.0.1:9090/targets
```

## Files

| Path | Purpose |
|------|---------|
| `helm/monitoring/values.yaml` | kube-prometheus-stack limits, retention, NodePort |
| `helm/monitoring/blackbox-values.yaml` | Odoo `/devops/health` probes |
| `scripts/install-monitoring.sh` | Helm install (Prometheus + Grafana + blackbox) |

## RAM note (4 GB VM)

Monitoring is capped (~512 Mi Prometheus, ~256 Mi Grafana). If the node OOMs, raise limits in `values.yaml` or disable blackbox.

## Sessions roadmap

| Session | Topic | Status |
|---------|--------|--------|
| A | Prometheus + Grafana core | This doc |
| B | Odoo dashboards | — |
| C | Loki + Promtail logs | — |
| D | Alertmanager rules | — |
| E | Nginx access + mark Phase 7 done | — |
