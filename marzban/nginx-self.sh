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

# Check if Nginx is already installed
if command -v nginx &> /dev/null; then
  echo "Nginx is already installed on this system."
  echo "This script supports only fresh installations on servers with unoccupied ports 80 and 8443."
  echo "Please remove Nginx first and run this script again."
  echo "You can uninstall Nginx using the following command:"
  echo "  sudo apt-get remove --purge -y nginx && sudo apt-get autoremove -y"
  exit 1
fi

# Check if ports 80 and 8443 are free
if ss -tlnp | grep -qE ":80\b|:8443\b"; then
  echo "Ports 80 or 8443 are already in use."
  echo "This script requires these ports to be free."
  echo "Please stop any processes using these ports and run the script again."
  exit 1
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
$SUDO apt-get update
$SUDO apt-get install -y nginx certbot python3-certbot-nginx
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
    # Блок-заглушка, чтобы отсеять любые случайные запросы на 80 порт
    server {
        listen 80 default_server;
        return 444;
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
        ssl_ciphers 'EECDH+ECDSA+AESGCM:EECDH+aRSA+AESGCM:EECDH+ECDSA+SHA384:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA384:EECDH+aRSA+SHA256:EECDH EDH+aRSA !aNULL !eNULL !LOW !3DES !MD5 !EXP !PSK !SRP !DSS !RC4';

        ssl_stapling on;
        ssl_stapling_verify on;
        resolver 1.1.1.1 valid=60s;
        resolver_timeout 2s;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/chain.pem;

        add_header Referrer-Policy 'no-referrer-when-downgrade' always;
        add_header Permissions-Policy 'interest-cohort=()' always;
        add_header Strict-Transport-Security 'max-age=31536000; includeSubDomains' always;
        add_header Content-Security-Policy \"script-src 'self' 'unsafe-inline'\";

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

echo "Checking Nginx configuration for errors..."
if ! $SUDO nginx -t; then
  echo "Nginx configuration contains errors. Please fix them before reloading."
  exit 1
fi

echo "Reloading Nginx to apply the new configuration..."
$SUDO systemctl reload nginx

echo "Removing temporary Certbot configuration..."
$SUDO rm -f /etc/nginx/sites-enabled/letsencrypt.conf
$SUDO rm -f /etc/nginx/sites-available/letsencrypt.conf

SELF_PATH="/usr/local/bin/self"
$SUDO bash -c "cat <<'EOF' > \"$SELF_PATH\"
#!/bin/bash

CERT_DIR="/etc/letsencrypt/live"
DOMAIN_FILE="/etc/nginx/current_domain.txt"
DOMAIN=""

if [[ -f \$DOMAIN_FILE ]]; then
  DOMAIN=\$(cat \$DOMAIN_FILE)
else
  echo "Domain file not found. Set DOMAIN manually."
  DOMAIN="example.com"
fi

help_menu() {
  echo ""
  echo "============================"
  echo " Nginx Management Utility "
  echo "============================"
  echo ""
  echo "Available Commands:"
  echo "  e             Edit /etc/nginx/nginx.conf"
  echo "  r             Restart Nginx"
  echo "  logs          Show Nginx logs"
  echo "  s|status      Show 'systemctl status nginx'"
  echo "  renew         Renew SSL certificates"
  echo "  cert-status   Check SSL certificate expiration"
  echo "  reinstall     Reload Nginx"
  echo "  uninstall     Remove Nginx, Certbot, and configurations"
  echo ""
  echo "Current Configuration Info:"
  echo "  Domain SNI: \$DOMAIN"
  echo "  Destination:  127.0.0.1:8443"
  echo "  Cert Path:    \$CERT_DIR/\$DOMAIN/"
  echo ""
}


cert_status() {
  if [[ -d \$CERT_DIR/\$DOMAIN ]]; then
    EXPIRY_DATE=\$(openssl x509 -enddate -noout -in \$CERT_DIR/\$DOMAIN/fullchain.pem | cut -d= -f2)
    echo "Certificate for \$DOMAIN expires on: \$EXPIRY_DATE"
  else
    echo "Certificate files not found for domain \$DOMAIN in \$CERT_DIR."
  fi
}

renew_certs() {
  echo "Renewing SSL certificates for \$DOMAIN..."
  certbot renew --nginx
  if [[ \$? -eq 0 ]]; then
    echo "Certificates successfully renewed."
  else
    echo "Failed to renew certificates. Check Certbot logs for details."
  fi
}

case "\$1" in
  e)
    echo "Opening /etc/nginx/nginx.conf..."
    nano /etc/nginx/nginx.conf
    ;;
  r)
    echo "Restarting Nginx..."
    systemctl restart nginx
    ;;
  logs)
    echo "Showing Nginx logs (Ctrl+C to exit)..."
    journalctl -u nginx -n 50 -f
    ;;
  s|status)
    echo "-- systemctl status nginx --"
    systemctl status nginx
    ;;
  renew)
    renew_certs
    ;;
  cert-status)
    cert_status
    ;;
  reinstall)
    echo "Reloading Nginx configuration..."
    systemctl reload nginx || systemctl restart nginx
    ;;
  uninstall)
    echo "Stopping and removing Nginx and Certbot..."
    systemctl stop nginx
    apt-get remove --purge -y nginx certbot python3-certbot-nginx
    apt-get autoremove -y
    rm -rf /etc/letsencrypt
    rm -rf /etc/nginx
    rm -f /usr/local/bin/self
    echo "All components removed."
    ;;
  help|"")
    help_menu
    ;;
  *)
    echo "Invalid command."
    help_menu
    ;;
esac
EOF"

$SUDO chmod +x "$SELF_PATH"
if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
 export PATH=$PATH:/usr/local/bin
fi

echo "Installation complete!"
echo "You can manage Nginx using the 'self' utility."
