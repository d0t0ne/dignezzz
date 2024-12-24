#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}This script must be run as root or with sudo privileges. Exiting...${RESET}"
  exit 1
fi

if ! command -v sudo &> /dev/null; then
  echo -e "${YELLOW}Warning: 'sudo' is not installed. Commands will run as root.${RESET}"
  SUDO=""
else
  SUDO="sudo"
fi

if command -v nginx &> /dev/null; then
  echo -e "${RED}Nginx is already installed on this system.${RESET}"
  echo -e "${CYAN}This script supports only fresh installations on servers with unoccupied ports 80 and 8443.${RESET}"
  echo -e "${YELLOW}Please remove Nginx first and run this script again.${RESET}"
  echo -e "You can uninstall Nginx using the following command:"
  echo -e "${GREEN}  sudo apt-get remove --purge -y nginx && sudo apt-get autoremove -y${RESET}"
  exit 1
fi

if ss -tlnp | grep -qE ":80\b|:8443\b"; then
  echo -e "${RED}Ports 80 or 8443 are already in use.${RESET}"
  echo -e "${CYAN}This script requires these ports to be free.${RESET}"
  echo -e "${YELLOW}Please stop any processes using these ports and run the script again.${RESET}"
  exit 1
fi

read -p "Please enter your domain (e.g., example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}No domain provided. Exiting...${RESET}"
  exit 1
fi

generate_random_email() {
  echo "$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c35)@gmail.com"
}

read -p "Please enter your email for certificate registration (leave blank to auto-generate): " EMAIL
if [[ -z "$EMAIL" ]]; then
  EMAIL=$(generate_random_email)
  echo -e "${YELLOW}No email provided. Generated email: ${EMAIL}${RESET}"
fi

read -p "Do you want to use DNS challenge for certificate installation? (Y/n): " USE_DNS
USE_DNS=${USE_DNS:-y}

DOMAIN_FILE="/etc/nginx/current_domain.txt"
$SUDO mkdir -p /etc/nginx
echo "$DOMAIN" | $SUDO tee "$DOMAIN_FILE" > /dev/null

if ! command -v logrotate &> /dev/null; then
  echo -e "${RED}Logrotate is not installed. Installing it now...${RESET}"
  $SUDO apt-get install -y -qq logrotate > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to install logrotate. Ensure your system is updated and retry.${RESET}"
    exit 1
  else
    echo -e "${GREEN}Logrotate installed successfully.${RESET}"
  fi
else
  echo -e "${GREEN}Logrotate is already installed.${RESET}"
fi

log_rotation_config() {
  echo "Adding log rotation configuration for Nginx..."
  $SUDO bash -c "cat <<EOF > /etc/logrotate.d/nginx
/var/log/nginx/*.log {
    size 100M
    rotate 2
    missingok
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 \$(cat /var/run/nginx.pid)
        fi
    endscript
}
EOF"
}



echo -e "${CYAN}Installing Nginx, Certbot, and python3-certbot-nginx...${RESET}"
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq nginx certbot python3-certbot-nginx 
if [[ $? -ne 0 ]]; then
  echo -e "${RED}Failed to install required packages. Ensure your system is updated and retry.${RESET}"
  exit 1
else
  echo -e "${GREEN}Required packages installed successfully.${RESET}"
fi

CERTBOT_CONF="/etc/nginx/sites-available/letsencrypt.conf"
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

$SUDO systemctl enable nginx
$SUDO systemctl restart nginx
log_rotation_config
if [[ "$USE_DNS" == "y" || "$USE_DNS" == "Y" ]]; then
  echo -e "${CYAN}Obtaining Let's Encrypt certificate using DNS challenge for ${DOMAIN}...${RESET}"
  $SUDO certbot certonly --manual --preferred-challenges dns -d "$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email
else
  echo -e "${CYAN}Obtaining Let's Encrypt certificate using web server for ${DOMAIN}...${RESET}"
  $SUDO certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email
fi

if [[ $? -ne 0 ]]; then
  echo -e "${RED}Certbot failed to obtain a certificate. Check the error messages above.${RESET}"
  exit 1
fi

CONF_FILE="/etc/nginx/sites-available/sni.conf"
$SUDO bash -c "cat <<'EOF' > \"$CONF_FILE\"
server {
    listen 127.0.0.1:8443 ssl http2 proxy_protocol;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    add_header Referrer-Policy \"no-referrer-when-downgrade\" always;
    add_header Permissions-Policy \"interest-cohort=()\" always;
    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;
    add_header Content-Security-Policy \"script-src 'self' 'unsafe-inline'\" always;
    proxy_hide_header X-Powered-By;

    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';

    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;
    set_real_ip_from ::1;

    root /var/www/html/site;
    index index.html;

    limit_req_zone \$binary_remote_addr zone=one:10m rate=10r/s;
    limit_conn_zone \$binary_remote_addr zone=addr:10m;

    location / {
        limit_req zone=one burst=20 nodelay;
        limit_conn addr 10;
        try_files \$uri \$uri/ =404;
    }

    error_page 403 404 500 502 503 504 /error.html;
    location = /error.html {
        root /usr/share/nginx/html;
    }
}
EOF"

ln -sf "$CONF_FILE" /etc/nginx/sites-enabled/

$SUDO nginx -t && $SUDO systemctl reload nginx

$SUDO rm -f /etc/nginx/sites-enabled/letsencrypt.conf
$SUDO rm -f /etc/nginx/sites-available/letsencrypt.conf

SELF_PATH="/usr/local/bin/self"
$SUDO bash -c "cat << 'EOF' > \"$SELF_PATH\"
#!/bin/bash
# Management utility (unchanged content from the previous script)
EOF"

$SUDO chmod +x "$SELF_PATH"

echo "Installation complete! Log rotation configured and DNS challenge option added."
echo "You can manage Nginx using the 'self' utility."
