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
  elif echo "$headers" | grep -iq "fastly"; then
    echo -e "${YELLOW}Используется CDN: Fastly (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "incapsula"; then
    echo -e "${YELLOW}Используется CDN: Imperva Incapsula (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "sucuri"; then
    echo -e "${YELLOW}Используется CDN: Sucuri (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "stackpath"; then
    echo -e "${YELLOW}Используется CDN: StackPath (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "cdn77"; then
    echo -e "${YELLOW}Используется CDN: CDN77 (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "edgecast"; then
    echo -e "${YELLOW}Используется CDN: Verizon Edgecast (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "keycdn"; then
    echo -e "${YELLOW}Используется CDN: KeyCDN (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "azurecdn"; then
    echo -e "${YELLOW}Используется CDN: Microsoft Azure CDN (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "aliyun"; then
    echo -e "${YELLOW}Используется CDN: Alibaba Cloud CDN (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "baidu"; then
    echo -e "${YELLOW}Используется CDN: Baidu Cloud CDN (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "tencent"; then
    echo -e "${YELLOW}Используется CDN: Tencent Cloud CDN (по заголовкам)${RESET}"
    CDN_RESULT=true
  elif echo "$headers" | grep -iq "cdn"; then
    echo -e "${YELLOW}Обнаружены признаки использования CDN (по заголовкам)${RESET}"
    CDN_RESULT=true
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
    elif echo "$cert_info" | grep -iq "Fastly"; then
      echo -e "${YELLOW}Используется CDN: Fastly (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "Incapsula"; then
      echo -e "${YELLOW}Используется CDN: Imperva Incapsula (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "Sucuri"; then
      echo -e "${YELLOW}Используется CDN: Sucuri (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "StackPath"; then
      echo -e "${YELLOW}Используется CDN: StackPath (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "CDN77"; then
      echo -e "${YELLOW}Используется CDN: CDN77 (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "Edgecast"; then
      echo -e "${YELLOW}Используется CDN: Verizon Edgecast (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "KeyCDN"; then
      echo -e "${YELLOW}Используется CDN: KeyCDN (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "Microsoft"; then
      echo -e "${YELLOW}Используется CDN: Microsoft Azure CDN (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "Alibaba"; then
      echo -e "${YELLOW}Используется CDN: Alibaba Cloud CDN (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "Baidu"; then
      echo -e "${YELLOW}Используется CDN: Baidu Cloud CDN (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
    elif echo "$cert_info" | grep -iq "Tencent"; then
      echo -e "${YELLOW}Используется CDN: Tencent Cloud CDN (по SSL-сертификату)${RESET}"
      CDN_RESULT=true
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
