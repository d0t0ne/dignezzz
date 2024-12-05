#!/bin/bash

if ! command -v docker &> /dev/null; then
  echo "Docker not found. Installing..."
  curl -fsSL https://get.docker.com | sh
  if ! command -v docker &> /dev/null; then
    echo "Docker installation failed. Check internet connection."
    exit 1
  fi
  echo "Docker installed."
else
  echo "Docker already installed."
fi

read -p "Domain (e.g., example.com): " DOMAIN

if [[ -z "$DOMAIN" ]]; then
  echo "Domain not provided. Exiting."
  exit 1
fi

CADDY_DIR="./caddy"
mkdir -p "$CADDY_DIR"

CADDYFILE_PATH="$CADDY_DIR/Caddyfile"
cat <<EOF > "$CADDYFILE_PATH"
{
    log {
        output file /var/log/caddy/error.log
        level INFO
    }

    auto_https on
    admin off
}

:80 {
    redir https://{host}{uri}
}

$DOMAIN {
    http2

    log {
        output file /var/log/caddy/access.log
    }

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
    }

    reverse_proxy * {
        to https://flickr.com
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Port {server_port}
        transport http {
            tls
            tls_server_name flickr.com
        }
        flush_interval -1
    }
}
EOF

COMPOSE_FILE="./docker-compose.yml"
cat <<EOF > "$COMPOSE_FILE"
services:
  caddy:
    image: caddy:latest
    container_name: caddy-container
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - $PWD/$CADDY_DIR/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    restart: unless-stopped

volumes:
  caddy_data:
  caddy_config:
EOF

echo "Caddyfile created."
echo "docker-compose.yml created."

docker compose up -d

if [[ $? -eq 0 ]]; then
  echo "Caddy started. https://$DOMAIN"
else
  echo "Caddy failed to start."
  exit 1
fi
