# Nginx reverse proxy (Phase 4)

Odoo is not exposed on public ports 8069/8072. Nginx on **:80** proxies to localhost.

## Order matters

1. Install Nginx on VM and create config **first**
2. Update compose (localhost bind + `PROXY_MODE`)
3. `terraform apply` (opens :80, removes public 8069/8072 NSG rules)

If you apply Terraform before Nginx is running, the site will be unreachable until Nginx is up.

## VM setup (one time)

Install Nginx and create `/etc/nginx/sites-available/odoo` on the VM (not stored in this repo):

```bash
sudo apt update && sudo apt install -y nginx

sudo tee /etc/nginx/sites-available/odoo << 'EOF'
upstream odoo {
    server 127.0.0.1:8069;
}

upstream odoochat {
    server 127.0.0.1:8072;
}

server {
    listen 80;
    server_name _;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP $remote_addr;
    client_max_body_size 100M;

    location / {
        proxy_pass http://odoo;
        proxy_redirect off;
    }

    location /websocket {
        proxy_pass http://odoochat;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/odoo
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

## After deploy

- **http://\<VM_IP\>/** — Odoo (no `:8069`)
- Direct **http://\<VM_IP\>:8069** — blocked (NSG + localhost bind)

## Terraform

`terraform/main.tf` allows inbound **80** only for HTTP. Ports **8069** and **8072** are not in the NSG.
