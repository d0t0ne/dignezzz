#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'
BOLD='\\033[1m'

CERT_DIR="/var/lib/marzban-vsem/certs"
SSH_CONFIG_FILE="/etc/nginx/ssh_config"

help_menu() {
  echo -e ""
  echo -e "${CYAN}=========================================${RESET}"
  echo -e "${GREEN}          Nginx Management Utility        ${RESET}"
  echo -e "${CYAN}=========================================${RESET}"
  echo -e ""
  echo -e "${GREEN}Available Commands:${RESET}"
  echo -e "  ${YELLOW}@install${RESET}         Install and configure Nginx"
  echo -e "  ${YELLOW}e${RESET}              Edit /etc/nginx/nginx.conf"
  echo -e "  ${YELLOW}r${RESET}              Restart Nginx"
  echo -e "  ${YELLOW}logs${RESET}           Show Nginx logs"
  echo -e "  ${YELLOW}s | status${RESET}     Show 'systemctl status nginx'"
  echo -e "  ${YELLOW}reinstall${RESET}      Reload Nginx configuration"
  echo -e "  ${YELLOW}uninstall${RESET}      Remove Nginx and configurations"
  echo -e ""
  echo -e "${BOLD}Current Configuration Info:${RESET}"
  echo -e "  ${CYAN}Domain SNI:${RESET} $(cat /etc/nginx/domain.txt 2>/dev/null || echo 'Not Configured')"
  echo -e "  ${CYAN}Destination:${RESET}  127.0.0.1:8443"
  echo -e "  ${CYAN}Cert Path:${RESET}    $CERT_DIR/$(cat /etc/nginx/domain.txt 2>/dev/null || echo 'Not Configured')/"
  echo -e ""
}

configure_ssh() {
  echo -e "${CYAN}Setting up SSH connection...${RESET}"
  read -p "Enter SSH username: " SSH_USER
  read -p "Enter SSH hostname or IP: " SSH_HOST
  read -p "Enter SSH port (default: 22): " SSH_PORT
  echo -e "Please paste the content of your SSH private key, press ENTER on a new line when finished: "
  SSH_KEY=""
  while IFS= read -r line; do
    if [[ -z $line ]]; then
      break
    fi
    SSH_KEY+="$line"
  done

  if [[ -z "$SSH_USER" || -z "$SSH_HOST" || -z "$SSH_KEY" ]]; then
    echo -e "${RED}Invalid input. All fields are required.${RESET}"
    return 1
  fi

  if [[ -z "$SSH_PORT" ]]; then
    SSH_PORT=22
  fi

  mkdir -p "$(dirname "$SSH_CONFIG_FILE")"
  echo "SSH_USER=$SSH_USER" > "$SSH_CONFIG_FILE"
  echo "SSH_HOST=$SSH_HOST" >> "$SSH_CONFIG_FILE"
  echo "SSH_PORT=$SSH_PORT" >> "$SSH_CONFIG_FILE"
  echo "SSH_KEY=$SSH_KEY" >> "$SSH_CONFIG_FILE"

  echo -e "${GREEN}SSH configuration updated.${RESET}"
}

renew_certs() {
  echo -e "${CYAN}Renewing certificates from main server...${RESET}"

  if [[ ! -f "$SSH_CONFIG_FILE" ]]; then
    echo -e "${RED}SSH configuration file not found. Please configure the SSH connection first.${RESET}"
    return 1
  fi

  source "$SSH_CONFIG_FILE"

  scp -P "$SSH_PORT" -i "$SSH_KEY" "$SSH_USER@$SSH_HOST:/var/lib/marzban/certs/fullchain.pem" "$CERT_DIR/fullchain.pem"
  scp -P "$SSH_PORT" -i "$SSH_KEY" "$SSH_USER@$SSH_HOST:/var/lib/marzban/certs/privkey.pem" "$CERT_DIR/key.pem"

  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Certificates successfully updated. Reloading Nginx...${RESET}"
    systemctl reload nginx
  else
    echo -e "${RED}Failed to copy certificates. Check SSH connection.${RESET}"
    return 1
  fi
}

install_nginx() {
  configure_ssh
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}SSH configuration failed. Exiting...${RESET}"
    exit 1
  fi

  echo -e "${CYAN}Installing Nginx...${RESET}"
  apt-get update -qq && apt-get install -y -qq nginx
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to install Nginx. Exiting...${RESET}"
    exit 1
  fi

  read -p "Please enter your domain (e.g., example.com): " DOMAIN
  if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}No domain provided. Exiting...${RESET}"
    exit 1
  fi

  echo "$DOMAIN" > /etc/nginx/domain.txt

  echo -e "${CYAN}Setting up Nginx configuration for domain...${RESET}"
  CONF_FILE="/etc/nginx/sites-available/$DOMAIN.conf"
  cat <<EOF > "$CONF_FILE"
server {
    listen 127.0.0.1:8443 ssl http2 proxy_protocol;
    server_name $DOMAIN;

    ssl_certificate $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/key.pem;
    ssl_trusted_certificate $CERT_DIR/fullchain.pem;

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
EOF

  renew_certs

  ln -sf "$CONF_FILE" /etc/nginx/sites-enabled/
  if nginx -t; then
    systemctl reload nginx
    echo -e "${GREEN}Nginx reloaded successfully with the new configuration.${RESET}"
  else
    echo -e "${RED}Nginx configuration test failed. Please check the configuration file.${RESET}"
    exit 1
  fi
}

install_script() {
  echo -e "${CYAN}Downloading and installing the script to /usr/local/bin/self...${RESET}"
  mkdir -p /usr/local/bin
  curl -sSL -o /usr/local/bin/self https://raw.githubusercontent.com/DigneZzZ/dignezzz.github.io/refs/heads/main/marzban/self.sh
  chmod +x /usr/local/bin/self

  if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
    echo -e "${CYAN}/usr/local/bin is not in PATH. Adding it...${RESET}"
    echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
    source ~/.bashrc
  fi

  echo -e "${GREEN}Script installed successfully. You can now use 'self' command.${RESET}"
}

case "$1" in
  install|@install)
    install_script
    install_nginx
    ;;
  e)
    echo -e "${CYAN}Opening /etc/nginx/nginx.conf...${RESET}"
    nano /etc/nginx/nginx.conf
    ;;
  r)
    echo -e "${CYAN}Restarting Nginx...${RESET}"
    systemctl restart nginx
    ;;
  logs)
    echo -e "${CYAN}Showing Nginx logs (Ctrl+C to exit)...${RESET}"
    journalctl -u nginx -n 50 -f
    ;;
  s|status)
    echo -e "${CYAN}-- systemctl status nginx --${RESET}"
    systemctl status nginx
    ;;
  reinstall)
    echo -e "${CYAN}Reloading Nginx configuration...${RESET}"
    systemctl reload nginx || systemctl restart nginx
    ;;
  @install-script)
    install_script
    ;;
  uninstall)
    echo -e "${YELLOW}Stopping and removing Nginx...${RESET}"
    systemctl stop nginx
    apt-get remove --purge -y nginx
    apt-get autoremove -y
    rm -rf /etc/nginx
    rm -f "$SELF_PATH"
    echo -e "${RED}Nginx and related files removed.${RESET}"
    ;;
  *)
    echo -e "${RED}Invalid command.${RESET}"
    help_menu
    ;;
esac
