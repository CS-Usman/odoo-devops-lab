# Phase 7 — Monitoring

**Status:** Sessions A–C done · Session D (alerts) in repo.

## Architecture

```text
k3s namespace: monitoring
├── Prometheus          metrics (3-day retention)
├── Grafana             dashboards + Explore
├── Loki                logs (72h retention)
├── Promtail            k8s pod logs + /var/log/nginx
├── node-exporter       VM CPU/RAM/disk
├── kube-state-metrics  pod status
├── blackbox-exporter   Odoo /devops/health probes
└── Alertmanager        routes alerts (null receiver in lab)
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

## Session C — Loki logs

After `./scripts/install-monitoring.sh` (or manual Loki/Promtail helm installs):

1. **Explore** → data source **Loki**
2. Query examples:

```logql
{namespace="odoo"}
```

```logql
{namespace="odoo", pod=~"odoo-prod.*"}
```

```logql
{job="nginx"}
```

| Source | Label |
|--------|--------|
| Odoo / postgres pods | `{namespace="odoo"}` |
| Host Nginx | `{job="nginx"}` |

Manual install (after git pull):

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update grafana
helm upgrade --install loki grafana/loki -n monitoring -f helm/monitoring/loki-values.yaml --wait --timeout 10m
helm upgrade --install promtail grafana/promtail -n monitoring -f helm/monitoring/promtail-values.yaml --wait --timeout 10m
helm upgrade monitoring prometheus-community/kube-prometheus-stack -n monitoring \
  -f helm/monitoring/values.yaml --set grafana.adminPassword=odoo-lab-change-me --wait --timeout 10m
```

## Session D — Alerts

Rules live in `helm/monitoring/prometheus-rules-odoo-lab.yaml`:

| Alert | Severity | When |
|-------|----------|------|
| OdooProdDown | critical | `/devops/health` probe fails 2m |
| OdooStagingDown | critical | staging health probe fails 2m |
| OdooProdPodNotReady | critical | prod pod not ready 5m |
| NodeMemoryLow | warning | &lt; 15% RAM free 5m |
| NodeDiskSpaceLow | warning | &lt; 15% disk on `/` 10m |
| OdooPodCrashLooping | warning | &gt; 3 restarts in 15m |
| PrometheusTargetDown | warning | scrape target down 5m |

### Install / upgrade alerts (VM)

```bash
cd ~/odoo-devops-lab && git pull
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f helm/monitoring/values.yaml \
  --set grafana.adminPassword=odoo-lab-change-me --wait --timeout 10m
kubectl apply -f helm/monitoring/prometheus-rules-odoo-lab.yaml
```

Or run the full script: `./scripts/install-monitoring.sh`

### View fired alerts

**Prometheus** (rule status Pending / Firing):

```bash
kubectl -n monitoring port-forward svc/monitoring-prometheus 9090:9090
# http://127.0.0.1:9090/alerts
```

**Alertmanager** (grouped notifications):

```bash
kubectl -n monitoring port-forward svc/monitoring-alertmanager 9093:9093
# http://127.0.0.1:9093
```

Lab default uses a **null receiver** (no email/Slack). Alerts still show in Prometheus and Alertmanager UIs.

### Add email notifications (optional)

Edit `helm/monitoring/values.yaml` under `alertmanager.config`:

```yaml
receivers:
  - name: email
    email_configs:
      - to: you@example.com
        from: alerts@yourdomain.com
        smarthost: smtp.example.com:587
        auth_username: you@example.com
        auth_password: secret
route:
  receiver: email
```

Then `helm upgrade monitoring ...` again.

### Test an alert

```bash
kubectl -n odoo scale deployment odoo-prod --replicas=0
# Wait ~2m → OdooProdDown fires in Prometheus / Alertmanager
kubectl -n odoo scale deployment odoo-prod --replicas=1
```

## Files

| Path | Purpose |
|------|---------|
| `helm/monitoring/values.yaml` | Stack limits, Grafana datasources (Prometheus + Loki) |
| `helm/monitoring/loki-values.yaml` | Loki Monolithic, 72h retention |
| `helm/monitoring/promtail-values.yaml` | Pod logs + Nginx host logs |
| `helm/monitoring/dashboards/odoo-lab-overview.json` | Session B dashboard |
| `helm/monitoring/blackbox-values.yaml` | Odoo health probes |
| `helm/monitoring/prometheus-rules-odoo-lab.yaml` | Session D alert rules |
| `scripts/install-monitoring.sh` | Full install |

## Sessions roadmap

| Session | Topic | Status |
|---------|--------|--------|
| A | Prometheus + Grafana core | Done |
| B | Odoo DevOps Lab dashboard | Done |
| C | Loki + Promtail logs | Done |
| D | Alertmanager rules | Done (deploy on VM) |
| E | Nginx access + mark Phase 7 done | — |
