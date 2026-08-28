# Nginx reverse proxy (Phase 4)

Odoo is not exposed on public ports 8069/8072. Nginx on **:80** proxies to localhost.

## Order matters

1. Install Nginx on VM and enable this config **first**
2. Update compose (localhost bind + `PROXY_MODE`)
3. `terraform apply` (opens :80, removes public 8069/8072 NSG rules)

If you apply Terraform before Nginx is running, the site will be unreachable until Nginx is up.

## VM setup (one time)

```bash
sudo apt update && sudo apt install -y nginx

sudo cp ~/odoo-devops-lab/deploy/nginx/odoo.conf /etc/nginx/sites-available/odoo
sudo ln -sf /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/odoo
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

## After deploy

- **http://\<VM_IP\>/** — Odoo (no `:8069`)
- Direct **http://\<VM_IP\>:8069** — blocked (NSG + localhost bind)

## Terraform

`terraform/main.tf` allows inbound **80** only for HTTP. Ports **8069** and **8072** are not in the NSG.
