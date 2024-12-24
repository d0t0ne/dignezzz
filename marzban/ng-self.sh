#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

CERT_DIR="/var/lib/marzban/certs"
DOMAIN_FILE="/etc/nginx/current_domain.txt"
SELF_PATH="/usr/local/bin/self"
SSH_CONFIG_FILE="/etc/marzban/ssh_config"

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

$SUDO mkdir -p /etc/nginx
$SUDO mkdir -p "$CERT_DIR"

echo -e "${CYAN}Installing Nginx...${RESET}"
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq nginx
if [[ $? -ne 0 ]]; then
  echo -e "${RED}Failed to install required packages. Ensure your system is updated and retry.${RESET}"
  exit 1
else
  echo -e "${GREEN}Nginx installed successfully.${RESET}"
fi

CONF_FILE="/etc/nginx/sites-available/sni.conf"
$SUDO bash -c "cat <<'EOF' > \"$CONF_FILE\"
server {
    listen 127.0.0.1:8443 ssl http2 proxy_protocol;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';

    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 valid=60s;
    resolver_timeout 2s;

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;
    set_real_ip_from ::1;

    add_header Strict-Transport-Security 'max-age=31536000; includeSubDomains' always;
    add_header X-Content-Type-Options 'nosniff' always;
    add_header X-Frame-Options 'DENY' always;
    add_header Referrer-Policy 'no-referrer' always;

    root /var/www/html/site;
    index index.html;

    location / {
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

$SUDO bash -c "cat << 'EOF' > \"$SELF_PATH\""
#!/bin/bash

CERT_DIR="/var/lib/marzban-vsem/certs"
SSH_CONFIG_FILE="$SSH_CONFIG_FILE"

configure_ssh() {
  echo -e "\${CYAN}Setting up SSH connection...\${RESET}"
  read -p "Enter SSH username: " SSH_USER
  read -p "Enter SSH hostname or IP: " SSH_HOST
  read -p "Enter SSH port (default: 22): " SSH_PORT
  read -p "Enter path to your SSH private key: " SSH_KEY

  if [[ -z \"\$SSH_USER\" || -z \"\$SSH_HOST\" || -z \"\$SSH_KEY\" ]]; then
    echo -e "\${RED}Invalid input. All fields are required.\${RESET}"
    return 1
  fi

  if [[ -z \"\$SSH_PORT\" ]]; then
    SSH_PORT=22
  fi

  mkdir -p "$(dirname \$SSH_CONFIG_FILE)"
  echo "SSH_USER=\$SSH_USER" > \$SSH_CONFIG_FILE
  echo "SSH_HOST=\$SSH_HOST" >> \$SSH_CONFIG_FILE
  echo "SSH_PORT=\$SSH_PORT" >> \$SSH_CONFIG_FILE
  echo "SSH_KEY=\$SSH_KEY" >> \$SSH_CONFIG_FILE

  echo -e "\${GREEN}SSH configuration updated.\${RESET}"
}

renew_certs() {
  echo -e "\${CYAN}Renewing certificates from main server...\${RESET}"

  if [[ ! -f \$SSH_CONFIG_FILE ]]; then
    echo -e "\${RED}SSH configuration file not found. Please configure the SSH connection first.\${RESET}"
    return 1
  fi

  source \$SSH_CONFIG_FILE

  scp -P \$SSH_PORT -i \$SSH_KEY \$SSH_USER@\$SSH_HOST:/var/lib/marzban/certs/fullchain.pem \$CERT_DIR/fullchain.pem
  scp -P \$SSH_PORT -i \$SSH_KEY \$SSH_USER@\$SSH_HOST:/var/lib/marzban/certs/privkey.pem \$CERT_DIR/key.pem

  if [[ $? -eq 0 ]]; then
    echo -e "\${GREEN}Certificates successfully updated. Reloading Nginx...\${RESET}"
    systemctl reload nginx
  else
    echo -e "\${RED}Failed to copy certificates. Check SSH connection.\${RESET}"
    return 1
  fi
}

cert_status() {
  if [[ -f "$CERT_DIR/fullchain.pem" ]]; then
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.pem" | cut -d= -f2)
    echo -e "\${GREEN}Certificate expiration date: \${CYAN}\$EXPIRY_DATE\${RESET}"
  else
    echo -e "\${RED}Certificate not found in $CERT_DIR\${RESET}"
  fi
}

uninstall() {
  echo -e "\${CYAN}Uninstalling Nginx and removing related configurations...\${RESET}"
  systemctl stop nginx
  apt-get remove --purge -y nginx
  apt-get autoremove -y
  rm -rf /etc/nginx
  rm -rf "$CERT_DIR"
  rm -f "$SELF_PATH"
  echo -e "\${GREEN}Uninstallation complete.\${RESET}"
}

help_menu() {
  echo -e "\n\${CYAN}=========================================\${RESET}"
  echo -e "\${BOLD}Nginx Management Utility\${RESET}"
  echo -e "\${CYAN}=========================================\${RESET}\n"
  echo -e "\${GREEN}Available Commands:\${RESET}"
  echo -e "  \${YELLOW}renew\${RESET}           Renew SSL certificates from main server"
  echo -e "  \${YELLOW}config\${RESET}          Configure SSH connection for certificate retrieval"
  echo -e "  \${YELLOW}cert-status\${RESET}     Show SSL certificate expiration status"
  echo -e "  \${YELLOW}restart\${RESET}         Restart Nginx service"
  echo -e "  \${YELLOW}logs\${RESET}            Show Nginx logs"
  echo -e "  \${YELLOW}uninstall\${RESET}       Uninstall Nginx and remove configurations"
  echo -e "  \${YELLOW}help\${RESET}            Show this help menu"
  echo -e \"\"
  echo -e \"\${BOLD}Current Configuration Info:\${RESET}\"
  echo -e \"  \${CYAN}Domain SNI:\${RESET} \$DOMAIN\"
  echo -e \"  \${CYAN}Destination:\${RESET}  127.0.0.1:8443\"
  echo -e \"  \${CYAN}Cert Path:\${RESET}    \$CERT_DIR/\$DOMAIN/\"
  echo -e \"\"
}

case "$1" in
  renew)
    renew_certs
    ;;
  config)
    configure_ssh
    ;;
  cert-status)
    cert_status
    ;;
  uninstall)
    uninstall
    ;;
  restart)
    echo -e "\${CYAN}Restarting Nginx...\${RESET}"
    systemctl restart nginx
    ;;
  logs)
    echo -e "\${CYAN}Showing Nginx logs (Ctrl+C to exit)...\${RESET}"
    journalctl -u nginx -n 50 -f
    ;;
  help)
    help_menu
    ;;
  *)
    echo -e "\${RED}Invalid command. Use 'help' for available commands.\${RESET}"
    ;;
esac
EOF"

$SUDO chmod +x "$SELF_PATH"

if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
  export PATH=$PATH:/usr/local/bin
fi

crontab -l | { cat; echo "0 0 * * * $SELF_PATH renew"; } | crontab -

echo -e "${GREEN}Installation complete! Certificates will be updated daily using 'self renew'.${RESET}"
