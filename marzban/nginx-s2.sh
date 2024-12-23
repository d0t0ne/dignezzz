#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then
  echo "This script must be run as root or with sudo privileges. Exiting..."
  exit 1
fi

if ! command -v sudo &> /dev/null; then
  echo "Warning: 'sudo' is not installed. Commands will run as root."
  SUDO=""
else
  SUDO="sudo"
fi

read -p "Please enter your domain (e.g., example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "No domain provided. Exiting..."
  exit 1
fi

generate_random_email() {
  echo "$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c35)@gmail.com"
}

read -p "Please enter your email for certificate registration (leave blank to auto-generate): " EMAIL
if [[ -z "$EMAIL" ]]; then
  EMAIL=$(generate_random_email)
  echo "No email provided. Generated email: $EMAIL"
fi

DOMAIN_FILE="/etc/nginx/current_domain.txt"
$SUDO mkdir -p /etc/nginx
echo "$DOMAIN" | $SUDO tee "$DOMAIN_FILE" > /dev/null

echo "Installing Nginx, Certbot, and python3-certbot-nginx..."
$SUDO apt update
$SUDO apt install -y nginx certbot python3-certbot-nginx
if [[ $? -ne 0 ]]; then
  echo "Failed to install required packages. Ensure your system is updated and retry."
  exit 1
fi

echo "Removing default /etc/nginx/sites-enabled/default..."
$SUDO rm -f /etc/nginx/sites-enabled/default

CERTBOT_CONF="/etc/nginx/sites-available/letsencrypt.conf"
echo "Creating minimal configuration for Certbot..."
$SUDO bash -c "cat <<EOF > \"$CERTBOT_CONF\"
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
    }

    location / {
        return 301 https://\$host:8443\$request_uri;
    }
}
EOF"

$SUDO ln -sf "$CERTBOT_CONF" /etc/nginx/sites-enabled/letsencrypt.conf

echo "Enabling and starting Nginx..."
$SUDO systemctl enable nginx
$SUDO systemctl restart nginx

echo "Obtaining Let's Encrypt certificate for $DOMAIN with email $EMAIL..."
$SUDO certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email
if [[ $? -ne 0 ]]; then
  echo "Certbot failed to obtain a certificate. Check the error messages above."
  exit 1
fi

echo "Configuring Nginx with a secure configuration..."
$SUDO bash -c "cat <<'EOF' > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
}

http {
    server {
        listen 80 default_server;
        return 444;
    }

    server {
        listen 8443 ssl;
        ssl_reject_handshake on;
    }

    server {
        listen 80;
        server_name $DOMAIN;
        return 301 https://\$server_name:8443\$request_uri;
    }

    server {
        listen 8443 ssl http2;
        server_name $DOMAIN;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers "EECDH+ECDSA+AESGCM EECDH+aRSA+AESGCM EECDH+ECDSA+SHA384 EECDH+ECDSA+SHA256 EECDH+aRSA+SHA384 EECDH+aRSA+SHA256 EECDH+aRSA+RC4 EECDH EDH+aRSA RC4 !aNULL !eNULL !LOW !3DES !MD5 !EXP !PSK !SRP !DSS";

        ssl_stapling on;
        ssl_stapling_verify on;
        resolver 1.1.1.1 valid=60s;
        resolver_timeout 2s;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/chain.pem;

        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Permissions-Policy \"interest-cohort=\\(\\)\" always;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header Content-Security-Policy "script-src 'self' 'unsafe-inline'";

        proxy_hide_header X-Powered-By;

        location / {
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Host \$host;
            proxy_set_header X-NginX-Proxy true;
            proxy_set_header X-Forwarded-Host \$http_host;
            proxy_pass http://localhost:5000;
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
            root /usr/share/nginx/html;
        }
    }
}
EOF"

echo "Removing temporary Certbot configuration..."
$SUDO rm -f /etc/nginx/sites-enabled/letsencrypt.conf
$SUDO rm -f /etc/nginx/sites-available/letsencrypt.conf

echo "Reloading Nginx to apply the new configuration..."
$SUDO systemctl reload nginx

echo "Installation complete!"
