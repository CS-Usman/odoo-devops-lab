# odoo-devops-lab

Personal lab for learning DevOps with Odoo 17 — Docker locally, Azure for production, automated deploys, backups.

## What's built

| Layer | Stack |
|-------|--------|
| App | Odoo 17 + `devops_server_monitor` module |
| Local dev | Docker Compose — Postgres + Odoo |
| Azure VM | k3s — odoo-prod + odoo-staging pods, Nginx on :80 |
| Database | Azure PostgreSQL Flexible Server v16 (private) |
| CI/CD | pre-commit, Gitleaks, Trivy, GHCR, SSH deploy, smoke test |
| Backups | `pg_dump` + filestore → Azure Blob (weekly cron) |
| Secrets | HashiCorp Vault + External Secrets → k8s |
| Monitoring | Prometheus, Grafana, Loki, Alertmanager on k3s |
| Bootstrap | Ansible playbook + cloud-init template |

**Live URLs:** `http://<VM_IP>/` (prod) · `http://<VM_IP>:8080/` (staging)

## Documentation

Start at **[docs/README.md](docs/README.md)**.

| Topic | Guide |
|-------|--------|
| Docker (local) | [docs/docker/README.md](docs/docker/README.md) |
| Terraform (VM, Postgres, Blob) | [docs/terraform/README.md](docs/terraform/README.md) |
| CI/CD | [docs/cicd/README.md](docs/cicd/README.md) |
| Nginx | [docs/nginx/README.md](docs/nginx/README.md) |
| Backups | [docs/backup/README.md](docs/backup/README.md) |
| k3s (prod + staging) | [docs/k3s/README.md](docs/k3s/README.md) |
| Vault + External Secrets | [docs/vault/README.md](docs/vault/README.md) |
| Monitoring | [docs/monitoring/README.md](docs/monitoring/README.md) |
| IP change | [docs/IP-CHANGE.md](docs/IP-CHANGE.md) |
| Runbook | [docs/RUNBOOK.md](docs/RUNBOOK.md) |

## Repo layout

```
├── addons/                    # Custom Odoo modules
├── ansible/                   # VM bootstrap playbook
├── helm/odoo/                 # Kubernetes Helm chart
├── k8s/                       # Traefik config for k3s
├── scripts/                   # backup, k3s install, deploy-k8s
├── terraform/                 # Azure VM, Postgres, Blob, cloud-init template
├── .github/workflows/         # ci.yml + docker-build.yml
├── docker-compose.yml         # Local dev
├── docker-compose.azure.yml   # VM → Azure Postgres
└── docs/
```

## Quick start (local)

```bash
docker compose up -d --build
pre-commit install    # optional — see docs/cicd/README.md
# http://localhost:8069
```

## Master plan progress

| Phase | Topic | Status |
|-------|--------|--------|
| 1–2 | Azure + Docker + Nginx + remote DB | Done |
| 3 | CI/CD (lint, Trivy, Gitleaks, smoke test) | Done |
| 4 | Terraform + Ansible bootstrap + runbook | Done |
| 4b | Blob backups + cron | Done |
| 5 | k3s + Helm (prod + staging) | Done — [docs/k3s/README.md](docs/k3s/README.md) |
| 6 | Vault + External Secrets | Done — [docs/vault/README.md](docs/vault/README.md) |
| 7 | Prometheus, Grafana, Loki, alerts | Done — [docs/monitoring/README.md](docs/monitoring/README.md) |
| 8 | Argo CD, GitOps, restore drill | Partial (Blob backups done) |
