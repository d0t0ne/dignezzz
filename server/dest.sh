#!/bin/bash

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

PING_RESULT=false
TLS_RESULT=false
CDN_RESULT=false

function check_and_install_command() {
  if ! command -v $1 &> /dev/null; then
    echo -e "${YELLOW}Utility $1 not found. Installing...${RESET}"
    sudo apt-get install -y $1 > /dev/null 2>&1
    if ! command -v $1 &> /dev/null; then
      echo -e "${RED}Error: failed to install $1. Please install it manually.${RESET}"
      exit 1
    fi
  fi
}

function check_host_port() {
  echo -e "${CYAN}Checking availability of $HOSTNAME on port $PORT...${RESET}"
  timeout 5 bash -c "</dev/tcp/$HOSTNAME/$PORT" &>/dev/null
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Host $HOSTNAME:$PORT is available${RESET}"
    HOST_PORT_AVAILABLE=true
  else
    echo -e "${YELLOW}Host $HOSTNAME:$PORT is unavailable${RESET}"
    HOST_PORT_AVAILABLE=false
  fi
}

function check_tls() {
  if [ "$PORT" == "443" ]; then
    echo -e "${CYAN}Checking TLS support for $HOSTNAME:$PORT...${RESET}"
    tls_version=$(echo | timeout 5 openssl s_client -connect $HOSTNAME:$PORT -tls1_3 2>/dev/null | grep "TLSv1.3")
    if [[ -n $tls_version ]]; then
      echo -e "${GREEN}TLS 1.3 is supported${RESET}"
      TLS_RESULT=true
    else
      tls_version=$(echo | timeout 5 openssl s_client -connect $HOSTNAME:$PORT 2>/dev/null | grep "Protocol" | awk '{print $2}')
      if [ -n "$tls_version" ]; then
        echo -e "${YELLOW}TLS 1.3 not supported. Using version: ${tls_version}${RESET}"
      else
        echo -e "${RED}Failed to detect TLS version${RESET}"
      fi
      TLS_RESULT=false
    fi
  else
    TLS_RESULT=true
  fi
}

function check_http_version() {
  echo -e "${CYAN}Checking HTTP support for $DOMAIN...${RESET}"

  HTTP2_SUPPORTED=false
  HTTP3_SUPPORTED=false

  http2_check=$(curl -I -s --max-time 5 --http2 https://$DOMAIN 2>/dev/null | grep -i "^HTTP/2")
  if [[ -n $http2_check ]]; then
    echo -e "${GREEN}HTTP/2 is supported (via curl)${RESET}"
    HTTP2_SUPPORTED=true
  else
    echo -e "${YELLOW}HTTP/2 is not supported (via curl)${RESET}"
  fi

  if [ "$HTTP2_SUPPORTED" != "true" ]; then
    alpn_protocols=$(echo | timeout 5 openssl s_client -alpn h2 -connect $DOMAIN:443 2>/dev/null | grep "ALPN protocol")
    if echo "$alpn_protocols" | grep -q "protocols:.*h2"; then
      echo -e "${GREEN}HTTP/2 is supported (via openssl)${RESET}"
      HTTP2_SUPPORTED=true
    else
      echo -e "${YELLOW}HTTP/2 is not supported (via openssl)${RESET}"
    fi

    if command -v nghttp &> /dev/null; then
      nghttp_output=$(timeout 5 nghttp -nv https://$DOMAIN 2>&1)
      if echo "$nghttp_output" | grep -q "The negotiated protocol: h2"; then
        echo -e "${GREEN}HTTP/2 is supported (via nghttp)${RESET}"
        HTTP2_SUPPORTED=true
      else
        echo -e "${YELLOW}HTTP/2 is not supported (via nghttp)${RESET}"
      fi
    else
      sudo apt-get install -y nghttp2-client > /dev/null 2>&1
      if command -v nghttp &> /dev/null; then
        nghttp_output=$(timeout 5 nghttp -nv https://$DOMAIN 2>&1)
        if echo "$nghttp_output" | grep -q "The negotiated protocol: h2"; then
          echo -e "${GREEN}HTTP/2 is supported (via nghttp)${RESET}"
          HTTP2_SUPPORTED=true
        else
          echo -e "${YELLOW}HTTP/2 is not supported (via nghttp)${RESET}"
        fi
      else
        echo -e "${RED}Failed to install nghttp for HTTP/2 check${RESET}"
      fi
    fi
  fi

  alpn_protocols=$(echo | timeout 5 openssl s_client -alpn h3 -connect $DOMAIN:443 2>/dev/null | grep "ALPN protocol")
  if echo "$alpn_protocols" | grep -iq "protocols:.*h3"; then
    echo -e "${GREEN}HTTP/3 is supported (via openssl)${RESET}"
    HTTP3_SUPPORTED=true
  else
    echo -e "${YELLOW}HTTP/3 is not supported (via openssl)${RESET}"
  fi

  if [ "$HTTP2_SUPPORTED" == "true" ]; then
    echo -e "${GREEN}Conclusion: HTTP/2 is supported${RESET}"
  else
    echo -e "${RED}Conclusion: HTTP/2 is not supported${RESET}"
  fi

  if [ "$HTTP3_SUPPORTED" == "true" ]; then
    echo -e "${GREEN}Conclusion: HTTP/3 is supported${RESET}"
  else
    echo -e "${YELLOW}Conclusion: HTTP/3 is not supported or couldn't be determined${RESET}"
  fi

  if [ "$HTTP2_SUPPORTED" == "true" ]; then
    HTTP_RESULT=true
  else
    HTTP_RESULT=false
  fi
}

function calculate_average_ping() {
  echo -e "${CYAN}Calculating average ping to $HOSTNAME...${RESET}"
  ping_output=$(ping -c 5 -q $HOSTNAME)
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to ping $HOSTNAME${RESET}"
    PING_RESULT=false
    avg_ping=1000
  else
    avg_ping=$(echo "$ping_output" | grep "rtt" | awk -F '/' '{print $5}')
    echo -e "${GREEN}Average ping: ${avg_ping} ms${RESET}"
    PING_RESULT=true
  fi
}

function determine_rating() {
  if [ "$PING_RESULT" = true ]; then
    if (( $(echo "$avg_ping < 2" | bc -l) )); then
      RATING=5
    elif (( $(echo "$avg_ping >= 2 && $avg_ping < 3" | bc -l) )); then
      RATING=4
    elif (( $(echo "$avg_ping >= 3 && $avg_ping < 5" | bc -l) )); then
      RATING=3
    elif (( $(echo "$avg_ping >= 5 && $avg_ping < 8" | bc -l) )); then
      RATING=2
    else
      RATING=1
    fi
    echo -e "${CYAN}Ping-based rating: ${RATING}/5${RESET}"
  else
    echo -e "${YELLOW}Failed to determine ping, setting rating to 0${RESET}"
    RATING=0
  fi
}

function check_cdn_headers() {
  echo -e "${CYAN}Analyzing HTTP headers for CDN detection...${RESET}"
  URL="$PROTOCOL://$HOSTNAME:$PORT"
  headers=$(curl -s -I --max-time 5 "$URL")

  if echo "$headers" | grep -iq "cloudflare"; then
    echo -e "${YELLOW}CDN detected: Cloudflare (by headers)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "akamai"; then
    echo -e "${YELLOW}CDN detected: Akamai (by headers)${RESET}"
    CDN_RESULT=true
  else
    echo -e "${GREEN}No CDN detected by headers${RESET}"
  fi
}

function check_cdn_certificate() {
  if [ "$PROTOCOL" == "https" ]; then
    echo -e "${CYAN}Analyzing SSL certificate for CDN detection...${RESET}"
    cert_info=$(echo | timeout 5 openssl s_client -connect $HOSTNAME:$PORT 2>/dev/null | openssl x509 -noout -issuer -subject)
    
    if echo "$cert_info" | grep -iq "Cloudflare"; then
      echo -e "${YELLOW}CDN detected: Cloudflare (by SSL certificate)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "Akamai"; then
      echo -e "${YELLOW}CDN detected: Akamai (by SSL certificate)${RESET}"
      CDN_RESULT=true
    else
      echo -e "${GREEN}No CDN detected by SSL certificate${RESET}"
    fi
  else
    echo -e "${YELLOW}HTTP protocol does not use SSL certificates. Skipping certificate check.${RESET}"
  fi
}

function check_cdn() {
  CDN_RESULT=false
  check_and_install_command curl
  check_cdn_headers
  if [ "$CDN_RESULT" == "true" ]; then return; fi

  check_cdn_certificate
  if [ "$CDN_RESULT" == "true" ]; then return; fi

  echo -e "${GREEN}No CDN detected${RESET}"
}

function check_dest_for_reality() {
  local reasons=()
  local negatives=()
  local positives=()

  if [ "$PING_RESULT" = true ]; then
    if [ $RATING -ge 3 ]; then
      positives+=("Ping rating: ${RATING}/5")
    else
      negatives+=("Ping rating below 3 (${RATING}/5)")
    fi
  else
    negatives+=("Failed to ping the host")
  fi

  if [ "$TLS_RESULT" = true ]; then
    positives+=("TLS 1.3 is supported")
  else
    negatives+=("TLS 1.3 is not supported")
  fi
  if [ "$HTTP_RESULT" == "true" ]; then
    positives+=("HTTP/2 is supported")
  else
    reasons+=("HTTP/2 is not supported")
  fi

  if [ "$CDN_RESULT" = false ]; then
    positives+=("CDN is not used")
  else
    negatives+=("CDN is used")
  fi

  echo -e "\n${CYAN}===== Check Results =====${RESET}"

  if [ ${#negatives[@]} -eq 0 ]; then
    echo -e "${GREEN}The site is suitable as a destination for Reality for the following reasons:${RESET}"
    for positive in "${positives[@]}"; do
      echo -e "${GREEN}- $positive${RESET}"
    done
  else
    if [ ${#negatives[@]} -eq 1 ] && [ "${negatives[0]}" == "CDN is used" ]; then
      echo -e "${YELLOW}The site is not recommended for the following reasons:${RESET}"
      for negative in "${negatives[@]}"; do
        echo -e "${YELLOW}- $negative${RESET}"
      done
    else
      echo -e "${RED}The site is NOT suitable for the following reasons:${RESET}"
      for negative in "${negatives[@]}"; do
        echo -e "${YELLOW}- $negative${RESET}"
      done
    fi

    if [ ${#positives[@]} -gt 0 ]; then
      echo -e "\n${GREEN}Positive aspects:${RESET}"
      for positive in "${positives[@]}"; do
        echo -e "${GREEN}- $positive${RESET}"
      done
    fi
  fi
}

if [ -z "$1" ]; then
  echo -e "${RED}Usage: $0 <host[:port]>${RESET}"
  exit 1
fi

INPUT="$1"
if [[ $INPUT == *":"* ]]; then
  HOSTNAME=$(echo $INPUT | cut -d':' -f1)
  PORT=$(echo $INPUT | cut -d':' -f2)
else
  HOSTNAME="$INPUT"
  PORT=""
fi

if [ -z "$PORT" ]; then
  PORTS=(443 80)
else
  PORTS=($PORT)
fi

check_and_install_command openssl
check_and_install_command ping
check_and_install_command bc

HOST_AVAILABLE=false

for PORT in "${PORTS[@]}"; do
  if [ "$PORT" == "443" ]; then
    PROTOCOL="https"
  else
    PROTOCOL="http"
  fi

  check_host_port
  if [ "$HOST_PORT_AVAILABLE" = true ]; then
    HOST_AVAILABLE=true
    check_tls
    check_http_version
    check_cdn
    break
  fi
done

if [ "$HOST_AVAILABLE" = false ]; then
  echo -e "${RED}Host $HOSTNAME is unavailable on ports ${PORTS[*]}${RESET}"
  exit 1
fi

calculate_average_ping
determine_rating
check_dest_for_reality
