# Monitoring (AKS)

Prometheus, Grafana, Loki, and Alertmanager via **kube-prometheus-stack** + Loki chart.

## Install

```bash
az aks get-credentials -g rg-odoo-devops-lab -n aks-odoo-devops-lab
export GRAFANA_ADMIN_PASSWORD='choose-a-strong-password'
./scripts/install-monitoring.sh
```

## Access Grafana

Do **not** expose Grafana on a public NodePort in production. Use port-forward:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
# http://127.0.0.1:3000  user: admin
```

## Logs

Grafana → Explore → Loki → `{namespace="odoo"}`

## Alerts

Custom rules: `helm/monitoring/prometheus-rules-odoo-lab.yaml`

Port-forward Prometheus and Alertmanager for debugging (see end of `install-monitoring.sh` output).

## Resources

Size node pool for monitoring + Odoo; on small clusters reduce Prometheus retention in `helm/monitoring/values.yaml`.
