# CI/CD — GitHub Actions → GHCR → Azure VM

Push to `main` builds a Docker image, pushes to GitHub Container Registry (GHCR), then deploys to the Azure VM over SSH.

## Flow

```text
git push main
  → GitHub Actions: build image
  → push ghcr.io/cs-usman/odoo-devops-lab:latest
  → SSH to VM: git pull, docker compose pull, up -d
```

Odoo on the VM uses **`docker-compose.azure.yml`** (Odoo only — DB is Azure Postgres).

## GitHub secrets

Set in repo **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|--------|
| `VM_HOST` | VM public IP (e.g. `172.198.71.246`) |
| `VM_USER` | `azureuser` |
| `VM_SSH_PRIVATE_KEY` | Private key for VM SSH |
| `GHCR_TOKEN` | GitHub PAT with `read:packages` (VM pulls image) |

## Workflow file

`.github/workflows/docker-build.yml` — two jobs:

1. **build** — build and push to GHCR on every push to `main`
2. **deploy** — SSH to VM, login to GHCR, pull latest compose stack

## VM one-time setup

```bash
# Clone repo on VM
git clone https://github.com/CS-Usman/odoo-devops-lab.git ~/odoo-devops-lab
cd ~/odoo-devops-lab

cp .env.azure.example .env
# edit .env — DB_* from Terraform, DOCKER_GID from: getent group docker | cut -d: -f3

sudo docker compose -f docker-compose.azure.yml up -d
```

After that, each push to `main` redeploys automatically.

## Manual deploy trigger

GitHub → **Actions** → **Build and push Docker image** → **Run workflow**.

## Check deploy on VM

```bash
cd ~/odoo-devops-lab
sudo docker compose -f docker-compose.azure.yml ps
sudo docker compose -f docker-compose.azure.yml logs -f odoo --tail=50
```

## What CI/CD does *not* do

- Does not run `terraform apply`
- Does not set VM `.env` secrets (DB, blob keys) — those stay on the VM
- Does not run backups — see [backup docs](../backup/README.md)
