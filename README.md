# odoo-devops-lab

Personal lab for learning DevOps with Odoo 17 — Docker locally, Azure for production, automated deploys, backups.

## What's built

| Layer | Stack |
|-------|--------|
| App | Odoo 17 + `devops_server_monitor` module |
| Local dev | Docker Compose — Postgres + Odoo |
| Azure VM | Odoo container, Nginx on :80 |
| Database | Azure PostgreSQL Flexible Server v16 (private) |
| CI/CD | GitHub Actions → GHCR → SSH deploy to VM |
| Backups | `pg_dump` + filestore → Azure Blob (weekly cron) |

**Live URL:** `http://<VM_IP>/` (Nginx → Odoo on localhost)

## Documentation

Start at **[docs/README.md](docs/README.md)**.

| Topic | Guide |
|-------|--------|
| Docker (local) | [docs/docker/README.md](docs/docker/README.md) |
| Terraform (VM, Postgres, Blob) | [docs/terraform/README.md](docs/terraform/README.md) |
| CI/CD | [docs/cicd/README.md](docs/cicd/README.md) |
| Nginx | [docs/nginx/README.md](docs/nginx/README.md) |
| Backups | [docs/backup/README.md](docs/backup/README.md) |

## Repo layout

```
├── addons/                    # Custom Odoo modules
├── scripts/                   # backup.sh, restore.sh
├── terraform/                 # Azure VM, Postgres, Blob
├── .github/workflows/         # Build + deploy pipeline
├── docker-compose.yml         # Local dev (Postgres + Odoo)
├── docker-compose.azure.yml     # VM (Odoo only → Azure Postgres)
└── docs/                      # Per-topic guides
```

## Quick start (local)

```bash
docker compose up -d --build
# http://localhost:8069
```

## Roadmap

- [x] Local Docker
- [x] Azure VM + private PostgreSQL
- [x] CI/CD to VM
- [x] Nginx + backups to Blob
- [ ] Staging VM / restore drill
- [ ] k8s, TLS, observability
