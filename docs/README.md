# Documentation

**New Azure subscription? Start here:** [GETTING-STARTED.md](GETTING-STARTED.md)

| Guide | Description |
|-------|-------------|
| [GETTING-STARTED.md](GETTING-STARTED.md) | `az login`, Terraform, kubectl, bootstrap from laptop |
| [aks/ARCHITECTURE.md](aks/ARCHITECTURE.md) | **Full stack** — tools, techniques, prod **2×** Odoo, Azure File RWX, Blob, ingress/TLS |
| [aks/README.md](aks/README.md) | AKS bootstrap, Helm, PgBouncer |
| [terraform/README.md](terraform/README.md) | VNet, AKS, Postgres (prod only), Blob |
| [cicd/README.md](cicd/README.md) | GitHub Actions, GHCR, GitOps |
| [gitops/README.md](gitops/README.md) | Argo CD applications |
| [backup/README.md](backup/README.md) | **Disaster recovery** — CronJob, Blob, restore, RPO/RTO, drills |
| [monitoring/README.md](monitoring/README.md) | Prometheus, Grafana, Loki |
| [secrets/README.md](secrets/README.md) | Azure Key Vault + External Secrets (default) |
| [aks/INGRESS.md](aks/INGRESS.md) | ingress-nginx, TLS (cert-manager), prod/staging URLs |
| [vault/README.md](vault/README.md) | HashiCorp Vault (optional) |
| [docker/README.md](docker/README.md) | Local Compose only |
| [RUNBOOK.md](RUNBOOK.md) | Day-2 operations |

**Path:** local Docker (optional) → Terraform → Key Vault + ESO → bootstrap → Argo CD (apps + **monitoring**) → ingress + **cert-manager** → **install-backup-cronjob** → refresh staging.

**DR:** Nightly backups on AKS; restore via [backup/README.md](backup/README.md).

**Live stack (example):** [GETTING-STARTED.md](GETTING-STARTED.md) · public Odoo URLs in [aks/INGRESS.md](aks/INGRESS.md) · logs in Grafana Explore → Loki `{namespace="odoo"}`.
