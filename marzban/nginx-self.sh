#!/bin/bash


# Step 1: Ask for domain
read -p "Please enter your domain (e.g., example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "No domain provided. Exiting..."
  exit 1
fi

# Step 2: Install Nginx, Certbot, python3-certbot-nginx
echo "Installing Nginx, Certbot, python3-certbot-nginx..."
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
if [[ $? -ne 0 ]]; then
  echo "Failed to install required packages."
  exit 1
fi

# Step 3: Remove default Nginx config
echo "Removing default /etc/nginx/sites-enabled/default..."
sudo rm -f /etc/nginx/sites-enabled/default

# Step 4: Create necessary directories for marzban
echo "Creating /var/lib/marzban/certs, /var/lib/marzban/work, /var/lib/marzban/logs..."
sudo mkdir -p /var/lib/marzban/certs
sudo mkdir -p /var/lib/marzban/work
sudo mkdir -p /var/lib/marzban/logs

# Step 5: Create a minimal config so that Certbot can pass HTTP challenge on port 80
# We'll place it in /etc/nginx/sites-available/letsencrypt.conf
echo "Creating minimal config for Let's Encrypt challenge..."
CERTBOT_CONF="/etc/nginx/sites-available/letsencrypt.conf"
sudo bash -c "cat <<EOF > \"$CERTBOT_CONF\"
server {
    listen 80;
    server_name $DOMAIN;

    # Location for ACME HTTP challenge
    location /.well-known/acme-challenge/ {
    }

    # Redirect everything else to HTTPS (on 8443)
    location / {
        return 301 https://\$host:8443\$request_uri;
    }
}
EOF"

# Symlink this config into sites-enabled
sudo ln -sf /etc/nginx/sites-available/letsencrypt.conf /etc/nginx/sites-enabled/letsencrypt.conf

# Step 6: Start/restart Nginx
echo "Enabling and (re)starting Nginx..."
sudo systemctl enable nginx
sudo systemctl restart nginx

# Step 7: Issue certificate using Certbot with custom config directories
# Certbot will store certificate files in /var/lib/marzban/certs/live/<DOMAIN>
echo "Obtaining Let's Encrypt certificate for $DOMAIN, storing in /var/lib/marzban..."
sudo certbot --nginx \
  --config-dir /var/lib/marzban/certs \
  --work-dir /var/lib/marzban/work \
  --logs-dir /var/lib/marzban/logs \
  -d "$DOMAIN"
if [[ $? -ne 0 ]]; then
  echo "Certbot failed to obtain a certificate. Check the error messages."
  exit 1
fi

# Step 8: Overwrite /etc/nginx/nginx.conf with a more secure config.
# This listens on port 8443 with advanced TLS/SSL settings,
# referencing the certs from /var/lib/marzban/certs/live/<DOMAIN>.
echo "Writing secure /etc/nginx/nginx.conf..."

sudo bash -c "cat <<EOF > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
}

http {

    # Close any direct IP requests on port 80
    server {
        listen 80 default_server;
        return 444;
    }

    # Reject SSL if SNI is not provided
    server {
        listen 8443 ssl;
        ssl_reject_handshake on;
    }

    # Redirect domain from 80 to 8443
    server {
        listen 80;
        server_name $DOMAIN;
        return 301 https://\$server_name:8443\$request_uri;
    }

    # Main HTTPS server on port 8443
    server {
        listen 8443 ssl http2;
        server_name $DOMAIN;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_ciphers \"EECDH+ECDSA+AESGCM EECDH+aRSA+AESGCM EECDH+ECDSA+SHA384 EECDH+ECDSA+SHA256 EECDH+aRSA+SHA384 EECDH+aRSA+SHA256 EECDH+aRSA+RC4 EECDH EDH+aRSA RC4 !aNULL !eNULL !LOW !3DES !MD5 !EXP !PSK !SRP !DSS\";

        # OCSP Stapling
        ssl_stapling on;
        ssl_stapling_verify on;
        resolver 1.1.1.1 valid=60s;
        resolver_timeout 2s;

        # Use the Let's Encrypt certs from /var/lib/marzban
        ssl_certificate /var/lib/marzban/certs/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /var/lib/marzban/certs/live/$DOMAIN/privkey.pem;
        ssl_trusted_certificate /var/lib/marzban/certs/live/$DOMAIN/fullchain.pem;

        # Security headers
        add_header Referrer-Policy \"no-referrer-when-downgrade\" always;
        add_header Permissions-Policy \"interest-cohort=()\" always;
        add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;
        add_header Content-Security-Policy \"script-src 'self' 'unsafe-inline'\";
        proxy_hide_header X-Powered-By;

        # Additional security checks
        if (\$host !~* ^(.+\\.)?$DOMAIN\$ ) { return 444; }
        if (\$scheme ~* https) { set \$safe 1; }
        if (\$ssl_server_name !~* ^(.+\\.)?$DOMAIN\$ ) { set \$safe \"\${safe}0\"; }
        if (\$safe = 10) { return 444; }

        if (\$request_uri ~ (\"|'|\\`|~|,|:|--|;|%|\\\$|&&|\\?\\?|0x00|0X00|\\||\\|\\{|\\}|\\[|\\]|<|>|\\...|\\../|///)) { set \$hack 1; }

        error_page 400 401 402 403 500 501 502 503 504 =404 /404;
        proxy_intercept_errors on;

        location / {
            # Example proxy pass - adapt to your upstream
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

# Remove the temporary Certbot config if you like
sudo rm -f /etc/nginx/sites-enabled/letsencrypt.conf
sudo rm -f /etc/nginx/sites-available/letsencrypt.conf

echo "Reloading Nginx to apply new /etc/nginx/nginx.conf..."
sudo systemctl reload nginx

echo "All done. Nginx listens on 8443. Certificates are in /var/lib/marzban/certs/live/$DOMAIN."
echo "Port 80 remains open for future renewals (HTTP challenge)."

################################################################################
# Create 'self' utility
################################################################################
SELF_PATH="/usr/local/bin/self"
sudo bash -c "cat <<'EOF' > \"$SELF_PATH\"
#!/bin/bash

# All messages in English. Code comments in English.

help_menu() {
  echo \"Usage: self [command]\"
  echo \"Commands:\"
  echo \"  e: Edit /etc/nginx/nginx.conf\"
  echo \"  r: Restart Nginx\"
  echo \"  logs: Show Nginx logs (last 50 lines + follow)\"
  echo \"  s|status: Show 'systemctl status nginx'\"
  echo \"  reinstall: Reload or restart Nginx\"
  echo \"  uninstall: Remove Nginx, Certbot, and configurations (including /var/lib/marzban)\"
  echo \"  help: Show this help menu\"
}

case \"\$1\" in
  e)
    echo \"Opening /etc/nginx/nginx.conf...\"
    sudo nano /etc/nginx/nginx.conf
    ;;
  r)
    echo \"Restarting Nginx...\"
    sudo systemctl restart nginx
    ;;
  logs)
    echo \"Showing Nginx logs... (Ctrl+C to exit)\"
    sudo journalctl -u nginx -n 50 -f
    ;;
  s|status)
    echo \"-- systemctl status nginx --\"
    systemctl status nginx
    ;;
  reinstall)
    echo \"Reloading or restarting Nginx...\"
    sudo systemctl reload nginx || sudo systemctl restart nginx
    ;;
  uninstall)
    echo \"Stopping and removing Nginx and Certbot...\"
    sudo systemctl stop nginx
    sudo apt remove --purge -y nginx certbot python3-certbot-nginx
    sudo apt autoremove -y

    echo \"Removing /var/lib/marzban... (careful!)\"
    sudo rm -rf /var/lib/marzban

    echo \"Removing /etc/nginx...\"
    sudo rm -rf /etc/nginx

    echo \"Removing 'self' utility...\"
    sudo rm -f /usr/local/bin/self

    echo \"All removed.\"
    ;;
  help|\"\")
    help_menu
    ;;
  *)
    echo \"Invalid command.\"
    help_menu
    ;;
esac
EOF"

sudo chmod +x "$SELF_PATH"

echo
echo "Installation complete!"
echo "You can manage Nginx using the 'self' utility. For example:"
echo "  self s         # show systemctl status"
echo "  self logs      # tail Nginx logs"
echo "  self e         # edit /etc/nginx/nginx.conf"
echo "  self uninstall # remove everything, including /var/lib/marzban"
echo
echo "Done."
