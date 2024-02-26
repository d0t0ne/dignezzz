#!/bin/bash

# Проверяем, установлены ли необходимые пакеты
if ! dpkg -s wget unzip >/dev/null 2>&1; then
  echo "Установка необходимых пакетов..."
  apt install -y wget unzip
fi
# Создаем папку /var/lib/marzban/xray-core
mkdir -p /var/lib/marzban/xray-core
# Переходим в папку /var/lib/marzban/xray-core
cd /var/lib/marzban/xray-core

# Скачиваем Xray-core
xray_version="1.8.8"
xray_filename="Xray-linux-64.zip"
xray_download_url="https://github.com/XTLS/Xray-core/releases/download/v${xray_version}/${xray_filename}"

echo "Скачивание Xray-core..."
wget "${xray_download_url}"

# Извлекаем файл из архива и удаляем архив
echo "Извлечение Xray-core..."
unzip "${xray_filename}"
rm "${xray_filename}"

# Поиск пути до папки Marzban-node и файла docker-compose.yml
marzban_node_dir=$(find / -type d -name "Marzban-node" -exec test -f "{}/docker-compose.yml" \; -print -quit)

if [ -z "$marzban_node_dir" ]; then
  echo "Папка Marzban-node с файлом docker-compose.yml не найдена"
  exit 1
fi

# Добавление строки XRAY_EXECUTABLE_PATH в каждое environment
sed -i '/environment:/!b;n;/XRAY_EXECUTABLE_PATH/!a\      XRAY_EXECUTABLE_PATH: "/var/lib/marzban/xray-core/xray"' "$marzban_node_dir/docker-compose.yml"
# Перезапускаем Marzban-node
echo "Перезапуск Marzban..."
cd $marzban_node_dir
docker compose up -d --force-recreate

echo "Обновление ядра на Marzban-node завершено. Ядро установлено версии $xray_version"
