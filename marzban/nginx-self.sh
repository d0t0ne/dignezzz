#!/bin/bash

###############################################################################
# This script installs Nginx and Certbot on Ubuntu/Debian, creates a minimal 
# HTTP config for Certbot, obtains a certificate for DOMAIN using default 
# certbot directories, copies the resulting cert files to /var/lib/marzban/*.pem,
# and applies a secure nginx.conf listening on port 8443.
# All user interaction and messages in English; code comments in English as well.
###############################################################################

# Step 1: Ask for domain
read -p "Please enter your domain (e.g. example.com): " DOMAIN
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

# Step 4: Create a minimal config for Let’s Encrypt on port 80
# We'll call it /etc/nginx/sites-available/letsencrypt.conf
CERTBOT_CONF="/etc/nginx/sites-available/letsencrypt.conf"
echo "Creating minimal config for Certbot challenge at $CERTBOT_CONF..."
sudo bash -c "cat <<EOF > \"$CERTBOT_CONF\"
server {
    listen 80;
    server_name $DOMAIN;

    # The challenge location for Certbot:
    location /.well-known/acme-challenge/ {
    }

    # Optionally redirect all other requests to HTTPS (port 8443)
    location / {
        return 301 https://\$host:8443\$request_uri;
    }
}
EOF"

# Symlink to sites-enabled
sudo ln -sf /etc/nginx/sites-available/letsencrypt.conf /etc/nginx/sites-enabled/letsencrypt.conf

# Step 5: Start/restart Nginx
echo "Enabling and restarting Nginx..."
sudo systemctl enable nginx
sudo systemctl restart nginx

# Step 6: Run Certbot to obtain the certificate (default directories in /etc/letsencrypt)
echo "Obtaining Let's Encrypt certificate for $DOMAIN..."
sudo certbot --nginx -d "$DOMAIN"
if [[ $? -ne 0 ]]; then
  echo "Certbot failed to obtain a certificate. Check the error messages above."
  exit 1
fi

# Step 7: Copy the issued certificate files to /var/lib/marzban/
echo "Copying certificate files to /var/lib/marzban..."
sudo mkdir -p /var/lib/marzban
sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem"  /var/lib/marzban/fullchain.pem
sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem"    /var/lib/marzban/privkey.pem
sudo cp "/etc/letsencrypt/live/$DOMAIN/chain.pem"      /var/lib/marzban/chain.pem
sudo chown root:root /var/lib/marzban/*.pem
sudo chmod 600 /var/lib/marzban/*.pem

# Step 8: Overwrite /etc/nginx/nginx.conf with a more secure config referencing /var/lib/marzban/*.pem
echo "Overwriting /etc/nginx/nginx.conf with advanced TLS configuration on port 8443..."

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

    # Close direct IP requests on port 80
    server {
        listen 80 default_server;
        return 444;
    }

    # Reject SSL if SNI is not provided
    server {
        listen 8443 ssl;
        ssl_reject_handshake on;
    }

    # Redirect from 80 to 8443
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

        # Use the cert files from /var/lib/marzban
        ssl_certificate /var/lib/marzban/fullchain.pem;
        ssl_certificate_key /var/lib/marzban/privkey.pem;
        ssl_trusted_certificate /var/lib/marzban/chain.pem;

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
            # Example proxy pass
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

# Remove temporary Certbot config if desired
echo "Removing the temporary letsencrypt.conf..."
sudo rm -f /etc/nginx/sites-enabled/letsencrypt.conf
sudo rm -f /etc/nginx/sites-available/letsencrypt.conf

# Reload Nginx
echo "Reloading Nginx..."
sudo systemctl reload nginx

echo "Nginx now listens on port 8443. Certificates are stored in /var/lib/marzban/{fullchain,privkey,chain}.pem."
echo "Port 80 remains open for future renewals (HTTP challenge)."

###############################################################################
# Create 'self' utility
###############################################################################
SELF_PATH="/usr/local/bin/self"
sudo bash -c "cat <<'EOF' > \"$SELF_PATH\"
#!/bin/bash

# All messages in English, code comments in English.

help_menu() {
  echo \"Usage: self [command]\"
  echo \"Commands:\"
  echo \"  e: Edit /etc/nginx/nginx.conf\"
  echo \"  r: Restart Nginx\"
  echo \"  logs: Show Nginx logs (last 50 lines + follow)\"
  echo \"  s|status: Show systemctl status nginx\"
  echo \"  reinstall: Reload or restart Nginx\"
  echo \"  uninstall: Remove Nginx, Certbot, and all config + /var/lib/marzban/*.pem\"
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
    echo \"Showing Nginx logs (Ctrl+C to exit)...\"
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

    echo \"Removing /etc/nginx...\"
    sudo rm -rf /etc/nginx

    echo \"Removing /var/lib/marzban...\"
    sudo rm -rf /var/lib/marzban

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
echo "You can manage Nginx using the 'self' utility. Examples:"
echo "  self s      # Show Nginx status"
echo "  self logs   # Follow Nginx logs"
echo "  self e      # Edit /etc/nginx/nginx.conf"
echo "  self uninstall  # Remove everything (including /var/lib/marzban/*.pem)"
echo
echo "Done."
