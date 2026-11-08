# Monitoring (AKS)

Prometheus, Grafana, Loki, Alertmanager, and Odoo health probes. **Source of truth is git** — Argo CD Applications under `k8s/argocd/applications/monitoring*.yaml` deploy the upstream Helm charts with values from `helm/monitoring/`.

## GitOps (production path)

```bash
az aks get-credentials -g rg-odoo-devops-lab -n aks-odoo-devops-lab
git push origin main   # includes monitoring Argo apps + k8s/monitoring/
./scripts/install-argocd.sh   # applies all Application manifests if not already
```

In the Argo UI you should see **Synced/Healthy** for: `monitoring`, `monitoring-manifests`, `monitoring-blackbox`, `monitoring-loki`, `monitoring-promtail`.

Change `grafana.adminPassword` in `helm/monitoring/values.yaml` (or move to a cluster secret + `existingSecret`) before exposing Grafana.

## One-shot bootstrap (no Argo yet)

```bash
cd "$(git rev-parse --show-toplevel)"   # repo root, not scripts/
export GRAFANA_ADMIN_PASSWORD='choose-a-strong-password'
./scripts/install-monitoring.sh
```

`install-monitoring.sh` alone is **not** on your `PATH` — always use `./scripts/...` from the repo root.

## Access Grafana

Do **not** expose Grafana on a public NodePort in production. Use port-forward:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
# http://127.0.0.1:3000  user: admin
```

## Logs

Grafana → Explore → Loki → `{namespace="odoo"}`

## Alerts

Custom rules: `helm/monitoring/prometheus-rules-odoo-lab.yaml` (synced via Application `monitoring-manifests`).

Port-forward Prometheus and Alertmanager for debugging (see end of `install-monitoring.sh` output).

## Resources

Size node pool for monitoring + Odoo; on small clusters reduce Prometheus retention in `helm/monitoring/values.yaml`.
