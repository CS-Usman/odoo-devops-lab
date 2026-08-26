# Terraform — Azure infra

## Step 1 — VM (done)

Linux VM + network + NSG for SSH and Odoo.

## Step 2 — Azure PostgreSQL (private)

Managed PostgreSQL Flexible Server in the **same VNet** as the VM. No public internet access — only the VM can reach the database.

### What `postgres.tf` adds

1. Subnet `10.0.2.0/24` (delegated for PostgreSQL)
2. Private DNS zone `postgres.database.azure.com`
3. PostgreSQL Flexible Server (v16, burstable B1ms)
4. Database `odoo_devops_lab`

### One-time: register provider

```bash
az provider register --namespace Microsoft.DBforPostgreSQL
az provider show --namespace Microsoft.DBforPostgreSQL --query registrationState
```

Wait until `Registered`.

### Apply from your laptop

Add to `terraform.tfvars` (copy from `terraform.tfvars.example`):

```hcl
postgres_admin_password = "admin"
```

If the server name is taken globally, change `postgres_server_name` too.

```bash
cd terraform
terraform plan
terraform apply

terraform output postgres_fqdn
terraform output postgres_database_name
```

### Point Odoo at Azure Postgres (on the VM)

**Option A — fresh database (simplest)**

```bash
cd ~/odoo-devops-lab
git pull

cp .env.azure.example .env
# edit .env — DB_HOST from terraform output, DB_USER/DB_PASSWORD from tfvars

sudo docker compose down
sudo docker compose -f docker-compose.azure.yml up -d --build
```

Open `http://<VM_IP>:8069`, create DB `odoo_devops_lab`, install modules.

**Option B — migrate existing Docker Postgres data**

On the VM, while the old stack is still running:

```bash
sudo docker compose exec db pg_dump -U odoo -Fc postgres > /tmp/odoo.dump
```

After Azure Postgres exists and `.env` is set:

```bash
# install client if needed
sudo apt-get update && sudo apt-get install -y postgresql-client

# restore (use FQDN + password from terraform)
pg_restore -h psql-odoo-devops-lab.postgres.database.azure.com \
  -U odooadmin -d odoo_devops_lab --no-owner --role=odooadmin /tmp/odoo.dump
```

Then switch compose file and restart Odoo:

```bash
sudo docker compose down
sudo docker compose -f docker-compose.azure.yml up -d --build
```

### Test DB connectivity from VM

```bash
sudo apt-get install -y postgresql-client
psql "host=$(cd terraform && terraform output -raw postgres_fqdn) user=odooadmin dbname=odoo_devops_lab sslmode=prefer"
```

### Local dev unchanged

Keep using `docker-compose.yml` on your laptop (Postgres in Docker). Azure uses `docker-compose.azure.yml`.

## Files

| File | Purpose |
|------|---------|
| `versions.tf` | Terraform + Azure provider |
| `variables.tf` | Inputs (VM + Postgres) |
| `main.tf` | Resource group, network, NSG, VM |
| `postgres.tf` | Private PostgreSQL Flexible Server |
| `outputs.tf` | Public IP, Postgres FQDN |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` (not committed) |

## Tear down

```bash
terraform destroy
```

Postgres deletion can take several minutes.
