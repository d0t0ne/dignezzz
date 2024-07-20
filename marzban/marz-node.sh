#!/bin/bash

# Установка sshpass
if ! command -v sshpass &> /dev/null; then
  echo "sshpass не найден, устанавливаю..."
  sudo apt-get update
  sudo apt-get install -y sshpass
else
  echo "sshpass уже установлен."
fi

# Путь к файлу реестра
REGISTRY_PATH="/opt/marz-node"
REGISTRY_FILE="$REGISTRY_PATH/list.json"
SSH_KEY_PATH="$HOME/.ssh/id_rsa_marz"

# Проверка и создание директории и файла реестра
if [ ! -d "$REGISTRY_PATH" ]; then
  sudo mkdir -p "$REGISTRY_PATH"
fi

if [ ! -f "$REGISTRY_FILE" ]; then
  echo "[]" > "$REGISTRY_FILE"
fi

# Функция для добавления нового сервера
function add_server() {
  read -p "Введите IP адрес: " ip
  read -p "Введите порт SSH (по умолчанию 22): " port
  port=${port:-22}
  read -p "Введите логин (по умолчанию root): " login
  login=${login:-root}
  read -s -p "Введите пароль: " password
  echo
  
  # Проверка существования SSH ключа
  if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "SSH ключ не найден, генерирую новый ключ..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
  else
    echo "SSH ключ найден, использую существующий ключ."
  fi
  
  # Копирование публичного ключа на удаленный сервер
  sshpass -p "$password" ssh-copy-id -i "$SSH_KEY_PATH.pub" -p $port $login@$ip
  
  # Обновление реестра
  timestamp=$(date +%Y-%m-%d\ %H:%M:%S)
  new_entry=$(jq -n --arg ip "$ip" --arg port "$port" --arg login "$login" --arg timestamp "$timestamp" \
  '{ip: $ip, port: $port, login: $login, auth_method: "ssh-key", last_update: $timestamp}')
  jq ". += [$new_entry]" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
  
  echo "Сервер добавлен и ключи успешно скопированы."
}

# Функция для отображения списка серверов
function list_servers() {
  jq '.' "$REGISTRY_FILE"
}

# Функция для редактирования сервера
function edit_server() {
  list_servers
  read -p "Введите IP адрес сервера для редактирования: " ip
  server_index=$(jq "map(.ip == \"$ip\") | index(true)" "$REGISTRY_FILE")
  
  if [ "$server_index" != "null" ]; then
    read -p "Введите новый IP адрес (оставьте пустым для сохранения текущего): " new_ip
    read -p "Введите новый порт SSH (оставьте пустым для сохранения текущего): " new_port
    read -p "Введите новый логин (оставьте пустым для сохранения текущего): " new_login
    
    if [ -n "$new_ip" ]; then
      jq ".[$server_index].ip = \"$new_ip\"" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    fi
    if [ -n "$new_port" ]; then
      jq ".[$server_index].port = \"$new_port\"" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    fi
    if [ -n "$new_login" ]; then
      jq ".[$server_index].login = \"$new_login\"" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    fi
    
    timestamp=$(date +%Y-%m-%d\ %H:%M:%S)
    jq ".[$server_index].last_update = \"$timestamp\"" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    
    echo "Сервер успешно обновлен."
  else
    echo "Сервер с таким IP не найден."
  fi
}

# Функция для отображения статуса демона
function status() {
  echo "Демон работает. (здесь может быть ваша логика проверки статуса)"
}

# Заготовка функции для выполнения скриптов на целевом сервере
function execute_scripts() {
  echo "Выполняется скрипт на целевом сервере..."
  # Здесь ваш код для выполнения на удаленном сервере
}

# Функция для установки на выбранный сервер
function install_on_server() {
  list_servers
  read -p "Введите IP адрес сервера для установки: " ip
  server_index=$(jq "map(.ip == \"$ip\") | index(true)" "$REGISTRY_FILE")
  
  if [ "$server_index" != "null" ]; then
    server=$(jq ".[$server_index]" "$REGISTRY_FILE")
    ip=$(echo "$server" | jq -r '.ip')
    port=$(echo "$server" | jq -r '.port')
    login=$(echo "$server" | jq -r '.login')
    
    echo "Подключение к серверу $ip..."
    ssh -i "$SSH_KEY_PATH" -p $port $login@$ip "$(typeset -f); execute_scripts"
    
    timestamp=$(date +%Y-%m-%d\ %H:%M:%S)
    jq ".[$server_index].last_update = \"$timestamp\"" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    
    echo "Скрипт успешно выполнен на сервере $ip."
  else
    echo "Сервер с таким IP не найден."
  fi
}

# Основная логика для работы с командами
case "$1" in
  add)
    add_server
    ;;
  list)
    list_servers
    ;;
  edit)
    edit_server
    ;;
  status)
    status
    ;;
  install)
    install_on_server
    ;;
  *)
    echo "Использование: $0 {add|list|edit|status|install}"
    ;;
esac
