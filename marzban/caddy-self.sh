#!/bin/bash


# Запрос домена у пользователя
read -p "Enter your domain (e.g., example.com): " DOMAIN

# Проверка, что домен указан
if [[ -z "$DOMAIN" ]]; then
  echo "Domain not provided. Exiting."
  exit 1
fi

# Проверка открытого порта 80 (обязателен для HTTP-челленджа)
REQUIRED_PORT=80
if lsof -i ":$REQUIRED_PORT" > /dev/null 2>&1; then
  echo "Port $REQUIRED_PORT is already in use. Please free it and try again."
  exit 1
fi

# Проверка, что 8443 свободен
ALT_PORT=8443
if lsof -i ":$ALT_PORT" > /dev/null 2>&1; then
  echo "Port $ALT_PORT is already in use. Please free it and try again."
  exit 1
fi

# Создание структуры директорий
CADDY_DIR="./caddy"
WWW_DIR="/var/www/mask-site"
LOG_DIR="/var/log/caddy"

mkdir -p "$CADDY_DIR" "$WWW_DIR" "$LOG_DIR"

# Проверка прав доступа
if [[ ! -w "$CADDY_DIR" || ! -w "$WWW_DIR" || ! -w "$LOG_DIR" ]]; then
  echo "Insufficient permissions for required directories. Exiting."
  exit 1
fi

# Генерация Caddyfile
CADDYFILE_PATH="$CADDY_DIR/Caddyfile"
cat <<EOF > "$CADDYFILE_PATH"
# 1) Блок :80 нужен, чтобы Let’s Encrypt мог проверять HTTP-челлендж
:80 {
    # Редиректим всё остальное на порт 8443, кроме ACME-челленджа, который Caddy обрабатывает автоматически
    @acme_challenge {
        path /.well-known/acme-challenge/*
    }
    handle @acme_challenge {
        # Тут Caddy сам ответит на челлендж
        route {
            # пусто — Caddy обрабатывает ACME автоматически
        }
    }

    # Всё, что не относится к челленджу, уводим на 8443
    handle {
        redir https://{host}:8443{uri}
    }
}

# 2) Основной сайт: слушаем 8443, получаем сертификат на DOMAIN
${DOMAIN}:8443 {
    bind 0.0.0.0

    tls {
        email dignezzz@gmail.com
        protocols tls1.2 tls1.3
        curves x25519
    }

    # Блокируем подозрительные запросы
    @blocked {
        path_regexp evil_paths (?i)^.*[(\.\.)|(%2e%2e)|(%252e)|(//)|(\\\\)].*\$
        header_regexp evil_headers (?i)(base64|bash|cmd|curl|database|delete|eval|exec|exploit|gcc|hack|injection|nmap|perl|python|scan|select|shell|sql|wget)
        remote_ip 0.0.0.0/0
        not remote_ip 127.0.0.1
    }
    respond @blocked 444

    root * $WWW_DIR
    file_server

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "no-referrer"
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self'; font-src 'self'; object-src 'none'; media-src 'self'; frame-src 'none'; form-action 'self'; base-uri 'self'"
        Permissions-Policy "interest-cohort=()"
        -Server
    }

    encode gzip

    log {
        output file $LOG_DIR/security.log
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
    # Пробрасываем только 80 и 8443
    ports:
      - "80:80"
      - "8443:8443"
    volumes:
      - $PWD/$CADDY_DIR/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
      - $WWW_DIR:$WWW_DIR
    restart: unless-stopped

volumes:
  caddy_data:
  caddy_config:
EOF

# Создание утилиты self
SELF_PATH="/usr/local/bin/self"
cat <<'EOF' > "$SELF_PATH"
#!/bin/bash

CADDYFILE="./caddy/Caddyfile"
COMPOSE_FILE="./docker-compose.yml"
CONTAINER_NAME="caddy-container"
BACKUP_DIR="/root/backup_caddy_$(date +%Y%m%d%H%M%S)"

help_menu() {
  echo "Usage: self [command]"
  echo "Commands:"
  echo "  e: Edit the Caddyfile"
  echo "  r: Restart the Caddy container"
  echo "  v: Verify the Caddyfile"
  echo "  f: Format the Caddyfile"
  echo "  help: Display this help menu"
  echo "  reinstall: Backup, recreate, and restart the Caddy service"
  echo "  uninstall: Stop and remove the Caddy service and files, with backup"
}

backup_files() {
  echo "Creating backup in $BACKUP_DIR..."
  mkdir -p "$BACKUP_DIR"
  cp -r "$CADDYFILE" "$COMPOSE_FILE" ./caddy_data ./caddy_config "$BACKUP_DIR" 2>/dev/null
  echo "Backup created at $BACKUP_DIR."
}

case "$1" in
  e)
    echo "Opening $CADDYFILE for editing..."
    nano "$CADDYFILE"
    ;;
  r)
    echo "Restarting Caddy container..."
    docker compose restart "$CONTAINER_NAME"
    ;;
  v)
    echo "Verifying $CADDYFILE syntax..."
    docker compose run --rm caddy caddy validate --config /etc/caddy/Caddyfile
    ;;
  f)
    echo "Formatting $CADDYFILE..."
    docker compose run --rm caddy caddy fmt --overwrite /etc/caddy/Caddyfile
    ;;
  reinstall)
    backup_files
    echo "Recreating and restarting Caddy service..."
    docker compose down
    docker compose up -d
    ;;
  uninstall)
    backup_files
    echo "Stopping and removing Caddy container..."
    docker compose down
    echo "Removing files..."
    rm -rf ./caddy ./docker-compose.yml ./caddy_data ./caddy_config
    echo "Removing self utility..."
    rm -f /usr/local/bin/self
    echo "Uninstall complete."
    ;;
  help|"")
    help_menu
    ;;
  *)
    echo "Invalid command."
    help_menu
    ;;
esac
EOF

chmod +x "$SELF_PATH"

# Вывод информации о созданных файлах
echo "Caddyfile created:"
cat "$CADDYFILE_PATH"

echo "docker-compose.yml created:"
cat "$COMPOSE_FILE"

echo "Utility 'self' created at $SELF_PATH with commands:"
echo "  e: Edit the Caddyfile"
echo "  r: Restart the Caddy container"
echo "  v: Verify the Caddyfile"
echo "  f: Format the Caddyfile"
echo "  help: Display this help menu"
echo "  reinstall: Backup, recreate, and restart the Caddy service"
echo "  uninstall: Stop and remove the Caddy service and files, with backup"

# Запуск контейнера
docker compose up -d

if [[ $? -eq 0 ]]; then
  echo "Caddy started on ports 80 and 8443, Let's Encrypt will run HTTP challenge on 80."
  echo "Domain: $DOMAIN (access via https://$DOMAIN:8443)"
  echo "Port 443 is FREE."
else
  echo "Caddy failed to start. Check configuration."
  exit 1
fi
