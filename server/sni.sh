#!/bin/bash

# Цвета для подсветки текста
GREEN="\033[32m"
RED="\033[31m"
CYAN="\033[36m"
YELLOW="\033[33m"
RESET="\033[0m"

TLS_RESULT=false
HTTP_RESULT=false
CDN_RESULT=false

# Функция для проверки и установки утилиты
function check_and_install_command() {
  if ! command -v $1 &> /dev/null; then
    echo -e "${YELLOW}Утилита $1 не найдена. Устанавливаю...${RESET}"
    sudo apt-get install -y $1 > /dev/null
    if ! command -v $1 &> /dev/null; then
      echo -e "${RED}Ошибка: не удалось установить $1. Установите её вручную.${RESET}"
      exit 1
    fi
  fi
}

# Проверка поддержки TLS 1.3 и вывод используемой версии TLS
function check_tls() {
  echo -e "${CYAN}Проверка поддержки TLS для $DOMAIN...${RESET}"
  tls_version=$(echo | timeout 5 openssl s_client -connect $DOMAIN:443 -tls1_3 2>/dev/null | grep "TLSv1.3")
  if [[ -n $tls_version ]]; then
    echo -e "${GREEN}TLS 1.3 поддерживается${RESET}"
    TLS_RESULT=true
  else
    tls_version=$(echo | timeout 5 openssl s_client -connect $DOMAIN:443 2>/dev/null | grep "Protocol" | awk '{print $2}')
    echo -e "${YELLOW}TLS 1.3 не поддерживается. Используемая версия: ${tls_version}${RESET}"
  fi
}

# Многоуровневая проверка поддержки HTTP/2 и HTTP/3
function check_http_version() {
  echo -e "${CYAN}Проверка поддержки HTTP для $DOMAIN...${RESET}"

  # Попытка 1: Проверка HTTP/2 с помощью curl
  http2_check=$(curl -I -s --max-time 5 --http2 https://$DOMAIN 2>/dev/null | grep -i "^HTTP/2")
  if [[ -n $http2_check ]]; then
    echo -e "${GREEN}HTTP/2 поддерживается${RESET}"
    HTTP_RESULT=true
    return
  fi

  # Попытка 2: Проверка HTTP/3 с помощью curl
  if curl -V | grep -q "with quiche"; then
    http3_check=$(curl -I --max-time 5 --http3 https://$DOMAIN 2>/dev/null)
    if echo "$http3_check" | grep -q "HTTP/3"; then
      echo -e "${GREEN}HTTP/3 поддерживается${RESET}"
      HTTP_RESULT=true
      return
    fi
  fi

  # Попытка 3: Использование openssl для проверки ALPN протоколов
  alpn_protocols=$(echo | timeout 5 openssl s_client -alpn h2 -connect $DOMAIN:443 2>/dev/null | grep "ALPN protocol")
  if echo "$alpn_protocols" | grep -q "h2"; then
    echo -e "${GREEN}HTTP/2 поддерживается (через openssl)${RESET}"
    HTTP_RESULT=true
    return
  fi

  # Попытка 4: Использование nghttp
  if command -v nghttp &> /dev/null; then
    nghttp_output=$(timeout 5 nghttp -nv https://$DOMAIN 2>&1)
    if echo "$nghttp_output" | grep -q "HTTP/2"; then
      echo -e "${GREEN}HTTP/2 поддерживается (через nghttp)${RESET}"
      HTTP_RESULT=true
      return
    fi
  else
    sudo apt-get install -y nghttp2-client > /dev/null 2>&1
    if command -v nghttp &> /dev/null; then
      nghttp_output=$(timeout 5 nghttp -nv https://$DOMAIN 2>&1)
      if echo "$nghttp_output" | grep -q "HTTP/2"; then
        echo -e "${GREEN}HTTP/2 поддерживается (через nghttp)${RESET}"
        HTTP_RESULT=true
        return
      fi
    fi
  fi

  # Попытка 5: Использование nmap
  if command -v nmap &> /dev/null; then
    nmap_output=$(timeout 10 nmap --script ssl-enum-alpns -p443 $DOMAIN 2>/dev/null)
    if echo "$nmap_output" | grep -q "h2"; then
      echo -e "${GREEN}HTTP/2 поддерживается (через nmap)${RESET}"
      HTTP_RESULT=true
      return
    fi
  else
    sudo apt-get install -y nmap > /dev/null 2>&1
    if command -v nmap &> /dev/null; then
      nmap_output=$(timeout 10 nmap --script ssl-enum-alpns -p443 $DOMAIN 2>/dev/null)
      if echo "$nmap_output" | grep -q "h2"; then
        echo -e "${GREEN}HTTP/2 поддерживается (через nmap)${RESET}"
        HTTP_RESULT=true
        return
      fi
    fi
  fi

  # Если ничего не найдено
  echo -e "${RED}Не удалось определить поддержку HTTP/2 или HTTP/3${RESET}"
}

# Проверка переадресации
function check_redirect() {
  echo -e "${CYAN}Проверка наличия переадресаций для $DOMAIN...${RESET}"
  redirect_check=$(curl -s -o /dev/null -w "%{redirect_url}" --max-time 5 https://$DOMAIN)
  if [ -n "$redirect_check" ]; then
    echo -e "${YELLOW}Переадресация найдена: $redirect_check${RESET}"
  else
    echo -e "${GREEN}Переадресация отсутствует${RESET}"
  fi
}

# Функция для анализа HTTP-заголовков
function check_cdn_headers() {
  echo -e "${CYAN}Анализ HTTP-заголовков для определения CDN...${RESET}"
  headers=$(curl -s -I --max-time 5 https://$DOMAIN)

  if echo "$headers" | grep -iq "cloudflare"; then
    echo -e "${YELLOW}Используется CDN: Cloudflare (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "akamai"; then
    echo -e "${YELLOW}Используется CDN: Akamai (по заголовкам)${RESET}"
    CDN_RESULT=true
  # Добавьте дополнительные проверки для других CDN
  else
    echo -e "${GREEN}По заголовкам CDN не обнаружен${RESET}"
  fi
}

# Функция для проверки ASN
function check_cdn_asn() {
  echo -e "${CYAN}Проверка ASN для определения CDN...${RESET}"
  ip=$(dig +short $DOMAIN | head -n1)
  if [ -z "$ip" ]; then
    echo -e "${RED}Не удалось получить IP-адрес домена${RESET}"
    return
  fi
  asn_info=$(whois -h whois.cymru.com " -v $ip" 2>/dev/null | tail -n1)
  asn=$(echo $asn_info | awk '{print $1}')
  owner=$(echo $asn_info | awk '{$1=""; $2=""; print $0}')
  
  if echo "$owner" | grep -iq "Cloudflare"; then
    echo -e "${YELLOW}Используется CDN: Cloudflare (по ASN)${RESET}"
    CDN_RESULT=true
  elif echo "$owner" | grep -iq "Akamai"; then
    echo -e "${YELLOW}Используется CDN: Akamai (по ASN)${RESET}"
    CDN_RESULT=true
  # Добавьте дополнительные проверки для других CDN
  else
    echo -e "${GREEN}По ASN CDN не обнаружен${RESET}"
  fi
}

# Функция для использования ipinfo.io
function check_cdn_ipinfo() {
  echo -e "${CYAN}Использование ipinfo.io для определения CDN...${RESET}"
  check_and_install_command jq
  ip=$(dig +short $DOMAIN | head -n1)
  if [ -z "$ip" ]; then
    echo -e "${RED}Не удалось получить IP-адрес домена${RESET}"
    return
  fi
  json=$(curl -s --max-time 5 https://ipinfo.io/$ip/json)
  org=$(echo $json | jq -r '.org')

  if echo "$org" | grep -iq "Cloudflare"; then
    echo -e "${YELLOW}Используется CDN: Cloudflare (через ipinfo.io)${RESET}"
    CDN_RESULT=true
  elif echo "$org" | grep -iq "Akamai"; then
    echo -e "${YELLOW}Используется CDN: Akamai (через ipinfo.io)${RESET}"
    CDN_RESULT=true
  # Добавьте дополнительные проверки для других CDN
  else
    echo -e "${GREEN}CDN не обнаружен через ipinfo.io${RESET}"
  fi
}

# Функция для анализа SSL-сертификата
function check_cdn_certificate() {
  echo -e "${CYAN}Анализ SSL-сертификата для определения CDN...${RESET}"
  cert_info=$(echo | timeout 5 openssl s_client -connect $DOMAIN:443 2>/dev/null | openssl x509 -noout -issuer -subject)
  
  if echo "$cert_info" | grep -iq "Cloudflare"; then
    echo -e "${YELLOW}Используется CDN: Cloudflare (по SSL-сертификату)${RESET}"
    CDN_RESULT=true
  elif echo "$cert_info" | grep -iq "Akamai"; then
    echo -e "${YELLOW}Используется CDN: Akamai (по SSL-сертификату)${RESET}"
    CDN_RESULT=true
  # Добавьте дополнительные проверки для других CDN
  else
    echo -e "${GREEN}CDN не обнаружен по SSL-сертификату${RESET}"
  fi
}

# Объединенная функция проверки CDN
function check_cdn() {
  CDN_RESULT=false
  check_cdn_headers
  if [ "$CDN_RESULT" == "true" ]; then return; fi

  check_cdn_asn
  if [ "$CDN_RESULT" == "true" ]; then return; fi

  check_cdn_ipinfo
  if [ "$CDN_RESULT" == "true" ]; then return; fi

  check_cdn_certificate
  if [ "$CDN_RESULT" == "true" ]; then return; fi

  echo -e "${GREEN}CDN не используется${RESET}"
}

# Итоговая проверка на SNI для Reality с пояснениями
function check_sni_for_reality() {
  local reasons=()
  
  if [ "$TLS_RESULT" != "true" ]; then
    reasons+=("Не поддерживается TLS 1.3")
  fi
  
  if [ "$HTTP_RESULT" != "true" ]; then
    reasons+=("Не поддерживается HTTP/2 или HTTP/3")
  fi
  
  if [ "$CDN_RESULT" == "true" ]; then
    reasons+=("Используется CDN")
  fi
  
  if [ ${#reasons[@]} -eq 0 ]; then
    echo -e "${GREEN}Сайт подходит как SNI для Reality${RESET}"
  else
    echo -e "${RED}Сайт не подходит как SNI для Reality по следующим причинам:${RESET}"
    for reason in "${reasons[@]}"; do
      echo -e "${YELLOW}- $reason${RESET}"
    done
  fi
}

# Проверка, введен ли домен
if [ -z "$1" ]; then
  echo -e "${RED}Использование: $0 <домен>${RESET}"
  exit 1
fi

DOMAIN=$1

# Проверка необходимых утилит и установка при необходимости
check_and_install_command openssl
check_and_install_command curl
check_and_install_command dig
check_and_install_command whois

# Выполнение проверок
check_tls
check_http_version
check_redirect
check_cdn

# Итоговая проверка
check_sni_for_reality
