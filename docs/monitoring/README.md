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

Grafana uses NodePort **30300**. Azure NSG must allow inbound **30300** (see `terraform/main.tf` rule `allow-grafana`) or use an SSH tunnel.

| Method | URL |
|--------|-----|
| Public (after `terraform apply`) | `http://<VM_PUBLIC_IP>:30300` |
| SSH tunnel (works immediately) | See below |

**SSH tunnel from your laptop** (works even before NSG is open):

```bash
ssh -i ~/.ssh/azure_vm_key -L 3000:127.0.0.1:3000 azureuser@<VM_IP> \
  'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80'
```

Open **http://127.0.0.1:3000** in Firefox (keep the SSH window open).

> Do **not** use `-L 30300:127.0.0.1:30300` alone — NodePort only works when the Grafana pod is Ready. Port-forward goes through the service directly.

Default login: `admin` / `odoo-lab-change-me` (or your `GRAFANA_ADMIN_PASSWORD`).

## What to check first

1. **Grafana → Dashboards → Kubernetes / Compute Resources / Node** — host CPU and memory.
2. **Grafana → Explore → Prometheus** — query `up` — targets should be `1`.
3. **Prometheus targets** — `odoo-health` probe for prod and staging.

Prometheus UI (not public by default):

```bash
kubectl -n monitoring port-forward svc/monitoring-prometheus 9090:9090
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
