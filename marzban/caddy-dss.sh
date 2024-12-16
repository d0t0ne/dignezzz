#!/bin/bash

# Запрос домена у пользователя
read -p "Enter your domain (e.g., example.com): " DOMAIN

# Проверка, что домен указан
if [[ -z "$DOMAIN" ]]; then
  echo "Domain not provided. Exiting."
  exit 1
fi

# Создание структуры директорий
CADDY_DIR="./caddy"
mkdir -p "$CADDY_DIR"

# Генерация Caddyfile с использованием указанного домена
CADDYFILE_PATH="$CADDY_DIR/Caddyfile"
cat <<EOF > "$CADDYFILE_PATH"
# Заглушка для HTTP
:80 {
    @ip {
        not host ${DOMAIN}
    }
    respond @ip 444
    respond 444
}

# Основной сайт
${DOMAIN}:8443 {
    bind 127.0.0.1

    @blocked {
        path_regexp evil_paths (?i)^.*[(\.\.)|(%2e%2e)|(%252e)|(//)|(\\\\)].*\$
        header_regexp evil_headers (?i)(base64|bash|cmd|curl|database|delete|eval|exec|exploit|gcc|hack|injection|nmap|perl|python|scan|select|shell|sql|wget)
        remote_ip 0.0.0.0/0
        not remote_ip 127.0.0.1
    }
    respond @blocked 444

    root * /var/www/mask-site
    file_server

    tls {
        protocols tls1.2 tls1.3
        curves x25519
        ciphers TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256
    }

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "no-referrer"
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self'; font-src 'self'; object-src 'none'; media-src 'self'; frame-src 'none'; form-action 'self'; base-uri 'self'"
        Permissions-Policy "interest-cohort=()"
        -Server
        -X-Powered-By
    }

    @scanners {
        header_regexp User-Agent (nmap|nikto|sqlmap|arachni|dirbuster|wpscan|sqlninja|wireshark|nessus|whatweb|metasploit|masscan|zgrab|gobuster|dirb)
    }
    respond @scanners 444

    @blocked_methods {
        method TRACE DELETE OPTIONS
    }
    respond @blocked_methods 444

    encode gzip

    log {
        output file /var/log/caddy/security.log
        format json
        level ERROR
    }
}
EOF

# Создание docker-compose.yml
COMPOSE_FILE="./docker-compose.yml"
cat <<EOF > "$COMPOSE_FILE"
services:
  caddy:
    image: caddy:latest
    container_name: caddy-container
    ports:
      - "80:80"
      - "443:443"
      - "8443:8443"
    volumes:
      - $PWD/$CADDY_DIR/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
      - /var/www/mask-site:/var/www/mask-site
    restart: unless-stopped

volumes:
  caddy_data:
  caddy_config:
EOF

# Вывод информации о созданных файлах
echo "Caddyfile created:"
cat "$CADDYFILE_PATH"

echo "docker-compose.yml created:"
cat "$COMPOSE_FILE"

# Запуск контейнера
docker compose up -d

if [[ $? -eq 0 ]]; then
  echo "Caddy successfully started. Domain: ${DOMAIN}"
else
  echo "Caddy failed to start. Check configuration."
  exit 1
fi
