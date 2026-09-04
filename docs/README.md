# Docs

Lab notes by phase. Each folder is a short overview + steps.

| Phase | Topic | Guide |
|-------|--------|--------|
| 1 | Docker (local) | [docker/README.md](docker/README.md) |
| 2 | Terraform — VM, Postgres, Blob | [terraform/README.md](terraform/README.md) |
| 3 | CI/CD — lint, Trivy, deploy, smoke test | [cicd/README.md](cicd/README.md) |
| 4 | Nginx reverse proxy | [nginx/README.md](nginx/README.md) |
| 4b | Backups — DB + filestore → Blob | [backup/README.md](backup/README.md) |
| 5 | k3s + Helm (prod + staging) | [k3s/README.md](k3s/README.md) |
| 6 | Vault + External Secrets | [vault/README.md](vault/README.md) |
| 7 | Monitoring — Prometheus, Grafana | [monitoring/README.md](monitoring/README.md) |

**Ops**

| Doc | Purpose |
|-----|---------|
| [IP-CHANGE.md](IP-CHANGE.md) | VM public IP changed → update `VM_HOST` |
| [RUNBOOK.md](RUNBOOK.md) | Rebuild drill, deploy failures, recovery |

**Suggested order:** Docker → Terraform → CI/CD → Nginx → Backups → k3s.
