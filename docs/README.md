# Documentation

**New Azure subscription? Start here:** [GETTING-STARTED.md](GETTING-STARTED.md)

| Guide | Description |
|-------|-------------|
| [GETTING-STARTED.md](GETTING-STARTED.md) | `az login`, Terraform, kubectl, bootstrap from laptop |
| [aks/ARCHITECTURE.md](aks/ARCHITECTURE.md) | 2 VMs, prod Azure DB, staging in-cluster, Blob filestore |
| [aks/README.md](aks/README.md) | AKS bootstrap, Helm, PgBouncer |
| [terraform/README.md](terraform/README.md) | VNet, AKS, Postgres (prod only), Blob |
| [cicd/README.md](cicd/README.md) | GitHub Actions, GHCR, GitOps |
| [gitops/README.md](gitops/README.md) | Argo CD applications |
| [backup/README.md](backup/README.md) | Backups and staging refresh |
| [monitoring/README.md](monitoring/README.md) | Prometheus, Grafana, Loki |
| [vault/README.md](vault/README.md) | Vault + External Secrets (optional) |
| [docker/README.md](docker/README.md) | Local Compose only |
| [RUNBOOK.md](RUNBOOK.md) | Day-2 operations |

**Path:** local Docker (optional) → Terraform → seed secrets → bootstrap → Argo CD → refresh staging → monitoring.
