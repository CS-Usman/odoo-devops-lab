# VM public IP changed

Use this when Terraform recreates the VM or the public IP changes.

## Our setup

- **PostgreSQL** is on a **private VNet** — no public firewall rule to update when the VM IP changes.
- **Odoo** is reached at `http://<VM_IP>/` via Nginx.

## Steps

### 1. Get the new IP

```bash
cd terraform
terraform output public_ip
# or
../scripts/update-vm-ip.sh
```

### 2. Update GitHub secret

**Settings → Secrets and variables → Actions → `VM_HOST`** → set to the new IP.

Without this, CI/CD deploy and smoke tests fail.

### 3. Verify

```bash
curl -I http://<NEW_IP>/
VM_HOST=<NEW_IP> ./scripts/smoke-test.sh
```

### 4. SSH

Update your SSH config or use:

```bash
ssh azureuser@<NEW_IP>
```

## Notes

- This lab uses a **static** public IP in Terraform (`allocation_method = Static`). IP usually stays the same unless you destroy/recreate the VM or public IP resource.
- `.env` on the VM does **not** need `VM_HOST` — only GitHub Actions uses it.
