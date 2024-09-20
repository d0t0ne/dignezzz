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
REDIRECT_RESULT=false

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

# Исправленная функция проверки поддержки TLS 1.3 и вывода используемой версии TLS
function check_tls() {
  echo -e "${CYAN}Проверка поддержки TLS для $DOMAIN...${RESET}"
  tls_version=$(echo | timeout 5 openssl s_client -connect $DOMAIN:443 -tls1_3 2>&1)
  if echo "$tls_version" | grep -q "TLSv1.3"; then
    echo -e "${GREEN}TLS 1.3 поддерживается${RESET}"
    TLS_RESULT=true
  else
    # Попытка соединиться без указания версии TLS
    tls_output=$(echo | timeout 5 openssl s_client -connect $DOMAIN:443 2>&1)
    protocol_line=$(echo "$tls_output" | grep -E "Protocol *:")
    if [[ -n $protocol_line ]]; then
      tls_used=$(echo "$protocol_line" | awk -F ': ' '{print $2}')
      echo -e "${YELLOW}TLS 1.3 не поддерживается. Используемая версия: ${tls_used}${RESET}"
    else
      echo -e "${RED}Не удалось определить используемую версию TLS${RESET}"
    fi
  fi
}

# Многоуровневая проверка поддержки HTTP/2 и HTTP/3
function check_http_version() {
  echo -e "${CYAN}Проверка поддержки HTTP для $DOMAIN...${RESET}"

  HTTP2_SUPPORTED=false
  HTTP3_SUPPORTED=false

  # Проверка HTTP/2 с помощью curl
  http2_check=$(curl -I -s --max-time 5 --http2 https://$DOMAIN 2>/dev/null | grep -i "^HTTP/2")
  if [[ -n $http2_check ]]; then
    echo -e "${GREEN}HTTP/2 поддерживается (через curl)${RESET}"
    HTTP2_SUPPORTED=true
  else
    echo -e "${YELLOW}HTTP/2 не поддерживается (через curl)${RESET}"
  fi

  # Дополнительные проверки для HTTP/2, если не найдено
  if [ "$HTTP2_SUPPORTED" != "true" ]; then
    # Использование openssl для проверки ALPN протоколов
    alpn_protocols=$(echo | timeout 5 openssl s_client -alpn h2 -connect $DOMAIN:443 2>/dev/null | grep "ALPN protocol")
    if echo "$alpn_protocols" | grep -q "protocols:.*h2"; then
      echo -e "${GREEN}HTTP/2 поддерживается (через openssl)${RESET}"
      HTTP2_SUPPORTED=true
    else
      echo -e "${YELLOW}HTTP/2 не поддерживается (через openssl)${RESET}"
    fi

    # Использование nghttp
    if command -v nghttp &> /dev/null; then
      nghttp_output=$(timeout 5 nghttp -nv https://$DOMAIN 2>&1)
      if echo "$nghttp_output" | grep -q "The negotiated protocol: h2"; then
        echo -e "${GREEN}HTTP/2 поддерживается (через nghttp)${RESET}"
        HTTP2_SUPPORTED=true
      else
        echo -e "${YELLOW}HTTP/2 не поддерживается (через nghttp)${RESET}"
      fi
    else
      sudo apt-get install -y nghttp2-client > /dev/null 2>&1
      if command -v nghttp &> /dev/null; then
        nghttp_output=$(timeout 5 nghttp -nv https://$DOMAIN 2>&1)
        if echo "$nghttp_output" | grep -q "The negotiated protocol: h2"; then
          echo -e "${GREEN}HTTP/2 поддерживается (через nghttp)${RESET}"
          HTTP2_SUPPORTED=true
        else
          echo -e "${YELLOW}HTTP/2 не поддерживается (через nghttp)${RESET}"
        fi
      else
        echo -e "${RED}Не удалось установить nghttp для проверки HTTP/2${RESET}"
      fi
    fi
  fi

  # Проверка поддержки HTTP/3

  # Метод 1: Использование openssl для проверки ALPN протоколов
  alpn_protocols=$(echo | timeout 5 openssl s_client -alpn h3 -connect $DOMAIN:443 2>/dev/null | grep "ALPN protocol")
  if echo "$alpn_protocols" | grep -iq "protocols:.*h3"; then
    echo -e "${GREEN}HTTP/3 поддерживается (через openssl)${RESET}"
    HTTP3_SUPPORTED=true
  else
    echo -e "${YELLOW}HTTP/3 не поддерживается (через openssl)${RESET}"
  fi

  # Вывод итогов
  if [ "$HTTP2_SUPPORTED" == "true" ]; then
    echo -e "${GREEN}Итог: HTTP/2 поддерживается${RESET}"
  else
    echo -e "${RED}Итог: HTTP/2 не поддерживается${RESET}"
  fi

  if [ "$HTTP3_SUPPORTED" == "true" ]; then
    echo -e "${GREEN}Итог: HTTP/3 поддерживается${RESET}"
  else
    echo -e "${YELLOW}Итог: HTTP/3 не поддерживается или не удалось определить${RESET}"
  fi

  # Установка HTTP_RESULT (только HTTP/2 влияет на итоговую оценку)
  if [ "$HTTP2_SUPPORTED" == "true" ]; then
    HTTP_RESULT=true
  else
    HTTP_RESULT=false
  fi
}


# Проверка переадресации
function check_redirect() {
  echo -e "${CYAN}Проверка наличия переадресаций для $DOMAIN...${RESET}"
  redirect_check=$(curl -s -o /dev/null -w "%{redirect_url}" --max-time 5 https://$DOMAIN)
  if [ -n "$redirect_check" ]; then
    echo -e "${YELLOW}Переадресация найдена: $redirect_check${RESET}"
    REDIRECT_RESULT=true
  else
    echo -e "${GREEN}Переадресация отсутствует${RESET}"
    REDIRECT_RESULT=false
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

# Итоговая проверка на SNI для Reality с подробным резюме
function check_sni_for_reality() {
  local reasons=()
  local positives=()

  # Проверка TLS 1.3
  if [ "$TLS_RESULT" == "true" ]; then
    positives+=("Поддерживается TLS 1.3")
  else
    reasons+=("Не поддерживается TLS 1.3")
  fi

  # Проверка HTTP/2
  if [ "$HTTP_RESULT" == "true" ]; then
    positives+=("Поддерживается HTTP/2")
  else
    reasons+=("Не поддерживается HTTP/2")
  fi

  # Проверка CDN
  if [ "$CDN_RESULT" == "true" ]; then
    reasons+=("Используется CDN")
  else
    positives+=("CDN не используется")
  fi

  # Проверка переадресации
  if [ "$REDIRECT_RESULT" == "false" ]; then
    positives+=("Переадресация отсутствует")
  else
    reasons+=("Найдена переадресация")
  fi

  echo -e "\n${CYAN}===== Результаты проверки =====${RESET}"

  if [ ${#reasons[@]} -eq 0 ]; then
    echo -e "${GREEN}Сайт подходит как SNI для Reality по следующим причинам:${RESET}"
    for positive in "${positives[@]}"; do
      echo -e "${GREEN}- $positive${RESET}"
    done
  else
    echo -e "${RED}Сайт не подходит как SNI для Reality по следующим причинам:${RESET}"
    for reason in "${reasons[@]}"; do
      echo -e "${YELLOW}- $reason${RESET}"
    done
    if [ ${#positives[@]} -gt 0 ]; then
      echo -e "\n${GREEN}Положительные моменты:${RESET}"
      for positive in "${positives[@]}"; do
        echo -e "${GREEN}- $positive${RESET}"
      done
    fi
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
