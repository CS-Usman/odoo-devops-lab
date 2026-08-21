# odoo-devops-lab

A personal DevOps lab built around a custom Odoo module (`devops_demo`). The goal is to practice production-style delivery on Azure: build and ship Odoo as a Docker image, provision infra with Terraform, deploy with GitHub Actions, then evolve to k3s, secrets (Vault), observability (Prometheus/Grafana/Loki), and GitOps (Argo CD).

- **App:** Odoo 17 + custom module
- **Database:** Azure Database for PostgreSQL (managed)
- **Runtime:** Docker → k3s on a single Azure VM
- **Access:** HTTP via VM public IP (no domain/SSL in this lab)

## Addons

| Module | Purpose |
|--------|---------|
| `devops_server_monitor` | Server health dashboard (CPU, RAM, disk, I/O, DB, filestore, Docker) + `/devops/health` and `/devops/metrics` endpoints |

### Install monitor module

Add `addons/devops_server_monitor` to your Odoo addons path, update apps list, install **DevOps Server Monitor**.

- Menu: **DevOps Monitor → Dashboard**
- Cron: collects metrics every 5 minutes
- CI: `curl http://<host>/devops/health` and `curl http://<host>/devops/metrics`