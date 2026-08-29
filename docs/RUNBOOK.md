# Runbook — rebuild and recover

Short ops notes for the lab VM.

## Rebuild VM from Terraform

Proves infra is reproducible (Phase 4 drill).

```bash
cd terraform
terraform plan    # B1s → B2s is usually update in-place (data kept)
terraform apply
./../scripts/update-vm-ip.sh    # update GitHub VM_HOST if IP changed
```

**Before resize:** `./scripts/backup.sh` on the VM.

On a **replaced** VM (not a simple size change):

```bash
# Option A — Ansible from laptop
cp ansible/inventory.example ansible/inventory   # set new IP
ansible-playbook -i ansible/inventory ansible/bootstrap.yml

# Option B — manual (see docs/cicd/README.md + docs/nginx/README.md)
```

Restore app data from Blob if needed: [backup/README.md](backup/README.md).

---

## Deploy failed in GitHub Actions

1. Actions log → deploy job
2. SSH to VM: `sudo docker compose -f docker-compose.azure.yml ps`
3. Logs: `sudo docker compose -f docker-compose.azure.yml logs odoo --tail=100`
4. Smoke test locally: `VM_HOST=<IP> ./scripts/smoke-test.sh`

---

## Odoo down but VM up

```bash
sudo systemctl status nginx
sudo docker compose -f docker-compose.azure.yml ps
curl -s http://127.0.0.1:8069/devops/health
curl -s http://127.0.0.1/devops/health
```

Restart:

```bash
sudo docker compose -f docker-compose.azure.yml restart odoo
sudo systemctl reload nginx
```

---

## Database issues

Postgres is Azure-managed (private). From VM:

```bash
source ~/odoo-devops-lab/.env
sudo docker run --rm -e PGPASSWORD="$DB_PASSWORD" postgres:16 \
  psql -h "$DB_HOST" -U "$DB_USER" -d "$ODOO_DB_NAME" -c 'SELECT 1'
```

Restore from backup: `./scripts/restore.sh YYYY-MM-DD`

---

## Backup / cron

```bash
tail /var/log/odoo-backup.log
./scripts/backup.sh
```

---

## IP changed

See [IP-CHANGE.md](IP-CHANGE.md).
