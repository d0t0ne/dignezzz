#!/bin/bash

# Цвета для подсветки текста
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

PING_RESULT=false
TLS_RESULT=false
CDN_RESULT=false

# Функция для проверки и установки утилиты
function check_and_install_command() {
  if ! command -v $1 &> /dev/null; then
    echo -e "${YELLOW}Утилита $1 не найдена. Устанавливаю...${RESET}"
    sudo apt-get install -y $1 > /dev/null 2>&1
    if ! command -v $1 &> /dev/null; then
      echo -e "${RED}Ошибка: не удалось установить $1. Установите её вручную.${RESET}"
      exit 1
    fi
  fi
}

# Функция для проверки доступности хоста и порта
function check_host_port() {
  echo -e "${CYAN}Проверка доступности $HOSTNAME на порту $PORT...${RESET}"
  timeout 5 bash -c "</dev/tcp/$HOSTNAME/$PORT" &>/dev/null
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Хост $HOSTNAME:$PORT доступен${RESET}"
    HOST_PORT_AVAILABLE=true
  else
    echo -e "${YELLOW}Хост $HOSTNAME:$PORT недоступен${RESET}"
    HOST_PORT_AVAILABLE=false
  fi
}

# Функция для проверки поддержки TLS 1.3
function check_tls() {
  if [ "$PORT" == "443" ]; then
    echo -e "${CYAN}Проверка поддержки TLS для $HOSTNAME:$PORT...${RESET}"
    tls_version=$(echo | timeout 5 openssl s_client -connect $HOSTNAME:$PORT -tls1_3 2>/dev/null | grep "TLSv1.3")
    if [[ -n $tls_version ]]; then
      echo -e "${GREEN}TLS 1.3 поддерживается${RESET}"
      TLS_RESULT=true
    else
      tls_version=$(echo | timeout 5 openssl s_client -connect $HOSTNAME:$PORT 2>/dev/null | grep "Protocol" | awk '{print $2}')
      if [ -n "$tls_version" ]; then
        echo -e "${YELLOW}TLS 1.3 не поддерживается. Используемая версия: ${tls_version}${RESET}"
      else
        echo -e "${RED}Не удалось определить используемую версию TLS${RESET}"
      fi
      TLS_RESULT=false
    fi
  else
    TLS_RESULT=true  # Предполагаем, что TLS не требуется на других портах
  fi
}

# Функция для вычисления среднего пинга
function calculate_average_ping() {
  echo -e "${CYAN}Вычисление среднего пинга до $HOSTNAME...${RESET}"
  ping_output=$(ping -c 5 -q $HOSTNAME)
  if [ $? -ne 0 ]; then
    echo -e "${RED}Не удалось выполнить пинг до $HOSTNAME${RESET}"
    PING_RESULT=false
    avg_ping=1000  # Устанавливаем высокое значение пинга
  else
    avg_ping=$(echo "$ping_output" | grep "rtt" | awk -F '/' '{print $5}')
    echo -e "${GREEN}Средний пинг: ${avg_ping} мс${RESET}"
    PING_RESULT=true
  fi
}

# Функция для определения рейтинга
function determine_rating() {
  if [ "$PING_RESULT" = true ]; then
    if (( $(echo "$avg_ping < 50" | bc -l) )); then
      RATING=5
    elif (( $(echo "$avg_ping >= 50 && $avg_ping < 100" | bc -l) )); then
      RATING=4
    elif (( $(echo "$avg_ping >= 100 && $avg_ping < 200" | bc -l) )); then
      RATING=3
    elif (( $(echo "$avg_ping >= 200 && $avg_ping < 300" | bc -l) )); then
      RATING=2
    else
      RATING=1
    fi
    echo -e "${CYAN}Рейтинг на основе пинга: ${RATING}/5${RESET}"
  else
    echo -e "${YELLOW}Не удалось определить пинг, рейтинг устанавливается на 0${RESET}"
    RATING=0
  fi
}

# Функция для анализа HTTP-заголовков на наличие CDN
function check_cdn_headers() {
  echo -e "${CYAN}Анализ HTTP-заголовков для определения CDN...${RESET}"
  URL="$PROTOCOL://$HOSTNAME:$PORT"
  headers=$(curl -s -I --max-time 5 "$URL")

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

# Функция для анализа SSL-сертификата на наличие CDN
function check_cdn_certificate() {
  if [ "$PROTOCOL" == "https" ]; then
    echo -e "${CYAN}Анализ SSL-сертификата для определения CDN...${RESET}"
    cert_info=$(echo | timeout 5 openssl s_client -connect $HOSTNAME:$PORT 2>/dev/null | openssl x509 -noout -issuer -subject)
    
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
  else
    echo -e "${YELLOW}Протокол HTTP не использует SSL-сертификаты. Пропускаем проверку сертификата.${RESET}"
  fi
}

# Объединенная функция проверки CDN
function check_cdn() {
  CDN_RESULT=false
  check_and_install_command curl
  check_cdn_headers
  if [ "$CDN_RESULT" == "true" ]; then return; fi

  check_cdn_certificate
  if [ "$CDN_RESULT" == "true" ]; then return; fi

  echo -e "${GREEN}CDN не используется${RESET}"
}

# Функция для вывода результатов проверки с измененной логикой
function check_dest_for_reality() {
  local reasons=()
  local negatives=()
  local positives=()

  # Проверка рейтинга по пингу
  if [ "$PING_RESULT" = true ]; then
    if [ $RATING -ge 3 ]; then
      positives+=("Рейтинг по пингу: ${RATING}/5")
    else
      negatives+=("Рейтинг по пингу ниже 3 (${RATING}/5)")
    fi
  else
    negatives+=("Не удалось выполнить пинг до хоста")
  fi

  # Проверка TLS 1.3
  if [ "$TLS_RESULT" = true ]; then
    positives+=("Поддерживается TLS 1.3")
  else
    negatives+=("Не поддерживается TLS 1.3")
  fi

  # Проверка CDN
  if [ "$CDN_RESULT" = false ]; then
    positives+=("CDN не используется")
  else
    negatives+=("Использование CDN")
  fi

  echo -e "\n${CYAN}===== Результаты проверки =====${RESET}"

  if [ ${#negatives[@]} -eq 0 ]; then
    echo -e "${GREEN}Сайт подходит как dest для Reality по следующим причинам:${RESET}"
    for positive in "${positives[@]}"; do
      echo -e "${GREEN}- $positive${RESET}"
    done
  else
    # Проверяем, является ли единственным отрицательным моментом использование CDN
    if [ ${#negatives[@]} -eq 1 ] && [ "${negatives[0]}" == "Использование CDN" ]; then
      echo -e "${YELLOW}Сайт не рекомендуется по следующим причинам:${RESET}"
      for negative in "${negatives[@]}"; do
        echo -e "${YELLOW}- $negative${RESET}"
      done
    else
      echo -e "${RED}Сайт НЕ ПОДХОДИТ по следующим причинам:${RESET}"
      for negative in "${negatives[@]}"; do
        echo -e "${YELLOW}- $negative${RESET}"
      done
    fi

    if [ ${#positives[@]} -gt 0 ]; then
      echo -e "\n${GREEN}Положительные моменты:${RESET}"
      for positive in "${positives[@]}"; do
        echo -e "${GREEN}- $positive${RESET}"
      done
    fi
  fi
}

# Проверка, введен ли хост
if [ -z "$1" ]; then
  echo -e "${RED}Использование: $0 <хост[:порт]>${RESET}"
  exit 1
fi

# Разбор хоста и порта
INPUT="$1"
if [[ $INPUT == *":"* ]]; then
  HOSTNAME=$(echo $INPUT | cut -d':' -f1)
  PORT=$(echo $INPUT | cut -d':' -f2)
else
  HOSTNAME="$INPUT"
  PORT=""
fi

# Если порт не указан, попробуем стандартные порты
if [ -z "$PORT" ]; then
  PORTS=(443 80)
else
  PORTS=($PORT)
fi

# Проверка необходимых утилит и установка при необходимости
check_and_install_command openssl
check_and_install_command ping
check_and_install_command bc

# Флаг для определения доступности хоста на каком-либо порту
HOST_AVAILABLE=false

# Попытка подключиться по разным портам
for PORT in "${PORTS[@]}"; do
  # Определяем протокол
  if [ "$PORT" == "443" ]; then
    PROTOCOL="https"
  else
    PROTOCOL="http"
  fi

  check_host_port
  if [ "$HOST_PORT_AVAILABLE" = true ]; then
    HOST_AVAILABLE=true
    check_tls
    check_cdn
    break
  fi
done

if [ "$HOST_AVAILABLE" = false ]; then
  echo -e "${RED}Хост $HOSTNAME недоступен на портах ${PORTS[*]}${RESET}"
  exit 1
fi

calculate_average_ping
determine_rating
check_dest_for_reality
