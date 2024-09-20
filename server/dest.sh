#!/bin/bash

# Проверка, что скрипт запущен с правами суперпользователя для установки пакетов
if [[ "$EUID" -ne 0 ]]; then
  echo -e "\e[33mУтилиты могут потребовать установки. Пожалуйста, запустите скрипт с правами sudo.\e[0m"
fi

# Функция для проверки и установки необходимых команд
check_and_install_command() {
  local cmd=$1
  local pkg=$2
  if ! command -v "$cmd" &> /dev/null; then
    echo -e "\e[33mУтилита $cmd не найдена. Устанавливаем...\e[0m"
    sudo apt-get update
    sudo apt-get install -y "$pkg"
    if ! command -v "$cmd" &> /dev/null; then
      echo -e "\e[31mОшибка: не удалось установить $cmd. Пожалуйста, установите вручную.\e[0m"
      exit 1
    fi
  fi
}

# Проверка и установка необходимых утилит
check_and_install_command "openssl" "openssl"
check_and_install_command "curl" "curl"
check_and_install_command "dig" "dnsutils"
check_and_install_command "whois" "whois"
check_and_install_command "ping" "iputils-ping"
check_and_install_command "nc" "netcat"

# Цветовые коды
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Инициализация результатов
declare -A results
results=(
  ["domain"]=""
  ["port"]=""
  ["tls_supported"]=false
  ["http2_supported"]=false
  ["cdn_used"]=false
  ["redirect_found"]=false
  ["ping"]=""
  ["rating"]=0
  ["cdn_provider"]=""
  ["cdns"]=""
  ["negatives"]=""
  ["positives"]=""
)

# Функция для проверки доступности порта
check_port_availability() {
  local domain=$1
  local port=$2
  timeout 5 bash -c "echo > /dev/tcp/$domain/$port" 2>/dev/null
  return $?
}

# Функция для проверки поддержки TLS 1.3
check_tls() {
  local domain=$1
  local port=$2
  echo -ne "${CYAN}Проверка поддержки TLS 1.3...\e[0m\r"
  output=$(echo | openssl s_client -connect "$domain:$port" -tls1_3 2>&1)
  if echo "$output" | grep -q "TLSv1.3"; then
    results["tls_supported"]=true
    results["positives"]+="- TLS 1.3 поддерживается\n"
    echo -e "${GREEN}TLS 1.3 поддерживается\e[0m"
  else
    tls_version=$(echo "$output" | grep -i "Protocol" | awk -F: '{print $2}' | tr -d ' ')
    if [[ -n "$tls_version" ]]; then
      results["negatives"]+="- TLS 1.3 не поддерживается (используется $tls_version)\n"
      echo -e "${YELLOW}TLS 1.3 не поддерживается ($tls_version)\e[0m"
    else
      results["negatives"]+="- Не удалось определить версию TLS\n"
      echo -e "${RED}Не удалось определить версию TLS\e[0m"
    fi
  fi
}

# Функция для проверки поддержки HTTP/2
check_http2() {
  local domain=$1
  local port=$2
  echo -ne "${CYAN}Проверка поддержки HTTP/2...\e[0m\r"
  http2_output=$(curl -I -s --http2 "https://$domain:$port" 2>&1)
  if echo "$http2_output" | grep -qi "HTTP/2"; then
    results["http2_supported"]=true
    results["positives"]+="- HTTP/2 поддерживается\n"
    echo -e "${GREEN}HTTP/2 поддерживается\e[0m"
  else
    http_version=$(curl -I -s "https://$domain:$port" 2>/dev/null | grep -i "HTTP/" | awk '{print $1}')
    if [[ -n "$http_version" ]]; then
      results["negatives"]+="- HTTP/2 не поддерживается (используется $http_version)\n"
      echo -e "${YELLOW}HTTP/2 не поддерживается ($http_version)\e[0m"
    else
      results["negatives"]+="- Не удалось определить версию HTTP\n"
      echo -e "${RED}Не удалось определить версию HTTP\e[0m"
    fi
  fi
}

# Функция для проверки использования CDN
check_cdn() {
  local domain=$1
  local port=$2
  echo -ne "${CYAN}Проверка использования CDN...\e[0m\r"
  declare -A cdn_providers=(
    ["cloudflare"]="Cloudflare"
    ["akamai"]="Akamai"
    ["fastly"]="Fastly"
    ["incapsula"]="Imperva Incapsula"
    ["sucuri"]="Sucuri"
    ["stackpath"]="StackPath"
    ["cdn77"]="CDN77"
    ["edgecast"]="Verizon Edgecast"
    ["keycdn"]="KeyCDN"
    ["azure"]="Microsoft Azure CDN"
    ["aliyun"]="Alibaba Cloud CDN"
    ["baidu"]="Baidu Cloud CDN"
    ["tencent"]="Tencent Cloud CDN"
  )
  
  headers=$(curl -I -s "https://$domain:$port" 2>/dev/null)
  header_str=$(echo "$headers" | tr '[:upper:]' '[:lower:]')
  
  for key in "${!cdn_providers[@]}"; do
    if echo "$header_str" | grep -q "$key"; then
      results["cdn_used"]=true
      results["cdn_provider"]="${cdn_providers[$key]}"
      results["cdns"]+="${cdn_providers[$key]}, "
      echo -e "${YELLOW}Используется CDN: ${cdn_providers[$key]}\e[0m"
      return
    fi
  done
  
  results["positives"]+="- CDN не используется\n"
  echo -e "${GREEN}CDN не используется\e[0m"
}

# Функция для проверки редиректов
check_redirect() {
  local domain=$1
  local port=$2
  echo -ne "${CYAN}Проверка редиректов...\e[0m\r"
  redirect=$(curl -s -o /dev/null -w "%{redirect_url}" -L "https://$domain:$port" 2>/dev/null)
  if [[ -n "$redirect" ]]; then
    results["redirect_found"]=true
    results["negatives"]+="- Найден редирект: $redirect\n"
    echo -e "${YELLOW}Найден редирект: $redirect\e[0m"
  else
    results["positives"]+="- Редиректов не найдено\n"
    echo -e "${GREEN}Редиректов не найдено\e[0m"
  fi
}

# Функция для расчета пинга
calculate_ping() {
  local domain=$1
  echo -ne "${CYAN}Расчет пинга...\e[0m\r"
  ping_output=$(ping -c 5 "$domain" 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    avg_ping=$(echo "$ping_output" | grep -i "rtt" | awk -F '/' '{print $5}')
    if [[ -n "$avg_ping" ]]; then
      results["ping"]="$avg_ping"
      # Оценка рейтинга
      if (( $(echo "$avg_ping <= 2" | bc -l) )); then
        results["rating"]=5
      elif (( $(echo "$avg_ping <= 3" | bc -l) )); then
        results["rating"]=4
      elif (( $(echo "$avg_ping <= 5" | bc -l) )); then
        results["rating"]=3
      elif (( $(echo "$avg_ping <= 8" | bc -l) )); then
        results["rating"]=2
      else
        results["rating"]=1
      fi
      
      if [[ ${results["rating"]} -ge 4 ]]; then
        results["positives"]+="- Средний пинг: ${avg_ping} ms (Рейтинг: ${results["rating"]}/5)\n"
        echo -e "${GREEN}Средний пинг: ${avg_ping} ms (Рейтинг: ${results["rating"]}/5)\e[0m"
      else
        results["negatives"]+="- Высокий пинг: ${avg_ping} ms (Рейтинг: ${results["rating"]}/5)\n"
        echo -e "${YELLOW}Высокий пинг: ${avg_ping} ms (Рейтинг: ${results["rating"]}/5)\e[0m"
      fi
    else
      results["negatives"]+="- Не удалось определить средний пинг\n"
      echo -e "${RED}Не удалось определить средний пинг\e[0m"
    fi
  else
    results["negatives"]+="- Не удалось выполнить пинг хоста\n"
    echo -e "${RED}Не удалось выполнить пинг хоста\e[0m"
  fi
}

# Функция для отображения результатов
display_results() {
  echo -e "\n${BOLD}${CYAN}===== Результаты проверки =====${RESET}\n"
  
  reasons=()
  positives=()
  
  if [[ "${results["tls_supported"]}" == true ]]; then
    positives+=("TLS 1.3 поддерживается")
  else
    reasons+=("TLS 1.3 не поддерживается")
  fi
  
  if [[ "${results["http2_supported"]}" == true ]]; then
    positives+=("HTTP/2 поддерживается")
  else
    reasons+=("HTTP/2 не поддерживается")
  fi
  
  if [[ "${results["cdn_used"]}" == true ]]; then
    cdn_list=${results["cdns"]%, }
    reasons+=("Используется CDN: $cdn_list")
  else
    positives+=("CDN не используется")
  fi
  
  if [[ "${results["redirect_found"]}" == false ]]; then
    positives+=("Редиректов не найдено")
  else
    reasons+=("Найден редирект")
  fi
  
  if [[ -n "${results["ping"]}" ]]; then
    if [[ "${results["rating"]}" -ge 4 ]]; then
      positives+=("Средний пинг: ${results["ping"]} ms (Рейтинг: ${results["rating"]}/5)")
    else
      reasons+=("Высокий пинг: ${results["ping"]} ms (Рейтинг: ${results["rating"]}/5)")
    fi
  else
    reasons+=("Не удалось определить средний пинг")
  fi
  
  acceptable=false
  if [[ "${results["rating"]}" -ge 4 ]]; then
    if [[ ${#reasons[@]} -eq 0 ]]; then
      acceptable=true
    elif [[ ${#reasons[@]} -eq 1 && "${reasons[0]}" == "Используется CDN: ${results["cdn_provider"]}" ]]; then
      acceptable=true
    else
      acceptable=false
    fi
  else
    acceptable=false
  fi
  
  if [[ "$acceptable" == true ]]; then
    echo -e "${BOLD}${GREEN}Сайт подходит для DEST for Reality по следующим причинам:${RESET}"
    for pos in "${positives[@]}"; do
      echo -e "${GREEN}- $pos${RESET}"
    done
  else
    echo -e "${BOLD}${RED}Сайт НЕ подходит для DEST for Reality по следующим причинам:${RESET}"
    for reason in "${reasons[@]}"; do
      echo -e "${YELLOW}- $reason${RESET}"
    done
    if [[ ${#positives[@]} -gt 0 ]]; then
      echo -e "\n${BOLD}${GREEN}Положительные моменты:${RESET}"
      for pos in "${positives[@]}"; do
        echo -e "${GREEN}- $pos${RESET}"
      done
    fi
  fi
  
  port_display=${results["port"]}
  if [[ -z "$port_display" ]]; then
    port_display="443/80"
  fi
  
  if [[ "$acceptable" == true ]]; then
    echo -e "\n${BOLD}${GREEN}Хост ${results["domain"]}:$port_display подходит в качестве dest${RESET}"
  else
    echo -e "\n${BOLD}${RED}Хост ${results["domain"]}:$port_display НЕ подходит в качестве dest${RESET}"
  fi
}

# Основная функция
main() {
  if [[ $# -ne 1 ]]; then
    echo -e "${RED}Использование: $0 <домен[:порт]>${RESET}"
    exit 1
  fi
  
  input=$1
  
  if [[ "$input" == *:* ]]; then
    domain=$(echo "$input" | cut -d':' -f1)
    port=$(echo "$input" | cut -d':' -f2)
  else
    domain="$input"
    port=""
  fi
  
  results["domain"]="$domain"
  results["port"]="$port"
  
  echo -e "\n${BOLD}${CYAN}Проверка хоста:${RESET} $domain"
  if [[ -n "$port" ]]; then
    echo -e "${BOLD}${CYAN}Порт:${RESET} $port"
    ports_to_check=("$port")
  else
    echo -e "${BOLD}${CYAN}Стандартные порты:${RESET} 443, 80"
    ports_to_check=(443 80)
  fi
  
  # Проверка доступности портов
  for p in "${ports_to_check[@]}"; do
    if check_port_availability "$domain" "$p"; then
      results["port"]="$p"
      echo -e "${GREEN}Порт $p доступен. Продолжаем проверку...${RESET}"
      break
    else
      echo -e "${YELLOW}Порт $p недоступен. Пробуем следующий порт...${RESET}"
    fi
  done
  
  if [[ -z "${results["port"]}" ]]; then
    echo -e "${RED}Хост $domain недоступен на портах ${ports_to_check[*]}${RESET}"
    exit 1
  fi
  
  # Параллельные проверки
  # Используем фоновые процессы и ждем их завершения
  check_tls "$domain" "${results["port"]}" &
  pid_tls=$!
  
  check_http2 "$domain" "${results["port"]}" &
  pid_http2=$!
  
  check_cdn "$domain" "${results["port"]}" &
  pid_cdn=$!
  
  check_redirect "$domain" "${results["port"]}" &
  pid_redirect=$!
  
  calculate_ping "$domain" &
  pid_ping=$!
  
  # Ожидание завершения всех проверок
  wait $pid_tls
  wait $pid_http2
  wait $pid_cdn
  wait $pid_redirect
  wait $pid_ping
  
  # Отображение результатов
  display_results
}

# Запуск основной функции
main "$@"
