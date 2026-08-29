# Docker notes

What we did to run Odoo 17 locally with Docker. Phase 1 of the lab.

## The idea

Two containers talk to each other:

- **postgres:16** — database (local only; Azure Postgres comes later)
- **odoo:17.0** — our app, built from the official image + our addons

`docker compose up` starts both. No Odoo install on the host, no systemd — the official Odoo image already has a startup script (`/entrypoint.sh`) that reads env vars and runs Odoo.

## Files we added

**Dockerfile** — start from official Odoo, copy our modules in:

```dockerfile
FROM odoo:17.0

USER root
COPY ./addons /mnt/extra-addons
RUN chown -R odoo:odoo /mnt/extra-addons
USER odoo
```

**docker-compose.yml** — Postgres + Odoo, port 8069, named volumes for data:

- `pgdata` → database files (don't lose these)
- `odoo-data` → Odoo filestore

DB connection for Odoo is via env: `HOST=db`, `USER=odoo`, `PASSWORD=odoo`.
`db` is the Postgres service name — not `localhost` from inside the container.

Don't forget the bottom of compose file:

```yaml
volumes:
  pgdata:
  odoo-data:
```

Without that, Compose throws `undefined volume "pgdata"`. We hit that once.

## Volumes — the part that confused me

**Named volume** = Docker keeps the data somewhere safe. DB and filestore use this.

**Bind mount** = `./addons:/mnt/extra-addons` maps your laptop folder into the container. Great while writing the module (no rebuild every edit). We removed it when module work was done — in prod, addons live inside the image from `COPY`, not a host folder.

After removing the bind mount, rebuild once (see commands below).

## Commands we ran

**1. Build and start (first time)**

```bash
cd /odoo17/custom/odoo-devops-lab
docker compose up --build
```

Later we used `-d` to run in the background:

```bash
docker compose up --build -d
```

**2. Create the database**

Browser → http://localhost:8069 → create database **`odoo_devops_lab`**.

**3. Install the monitor module**

```bash
docker compose exec odoo odoo \
  -i devops_server_monitor \
  -d odoo_devops_lab \
  --db_host=db \
  --db_user=odoo \
  --db_password=odoo \
  --stop-after-init

docker compose restart odoo
```

**4. Install web_responsive (optional)**

```bash
docker compose exec odoo odoo \
  -i web_responsive \
  -d odoo_devops_lab \
  --db_host=db \
  --db_user=odoo \
  --db_password=odoo \
  --stop-after-init

docker compose restart odoo
```

**5. Upgrade module after code changes**

```bash
docker compose exec odoo odoo \
  -u devops_server_monitor \
  -d odoo_devops_lab \
  --db_host=db \
  --db_user=odoo \
  --db_password=odoo \
  --stop-after-init

docker compose restart odoo
```

Hard refresh the browser after JS/CSS changes (`Ctrl+Shift+R`).

**6. Rebuild after removing the addons bind mount**

```bash
docker compose up --build -d
```

**7. Check endpoints**

```bash
curl http://localhost:8069/devops/health
curl http://localhost:8069/devops/metrics
```

**8. Confirm addons are in the container**

```bash
docker compose exec odoo ls /mnt/extra-addons
```

## Local vs later (Azure)

| Now | Later on VM |
|-----|-------------|
| Postgres in Docker | Azure managed Postgres |
| `docker compose build` | Pull image from GHCR |
| localhost:8069 | http://VM_IP:8069 |

That's it for Docker. Next up: push to GitHub, then Terraform.
