#!/bin/bash

# Пути и стандартные значения
sysctl_path="/etc/sysctl.conf"

# Цвета и форматирование
bold=$(tput bold)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
reset=$(tput sgr0)
clear
echo "${yellow}Данный скрипт оптимизирует сеть, путем выставления параметров SYSCTL${reset}"
echo "${yellow}Делаем бекап файла${reset}"
cp ${sysctl_path} /etc/sysctl.conf.backup
echo "Файл сохранен по пути /etc/sysctl.conf.backup"
sleep 1s
echo "${yellow}Скачиваем новый файл sysctl.conf${reset}"
wget "https://raw.githubusercontent.com/DigneZzZ/dignezzz.github.io/main/server/sysctl.conf" -q -O  ${sysctl_path}
echo "${yellow}Перезапускаем сеть${reset}"
sysctl -p
echo "${yellow}Готово!${reset}"

