#!/bin/bash

# Функция для установки цвета и вывода сообщения
print_message() {
    tput setaf $1
    echo $2
    tput sgr0
}

# Очистка экрана
clear

# Вывод заголовка
tput bold
print_message 2 "================================================================="
print_message 2 "===================Marzban XANMOD KERNEL INSTALLER==============="
print_message 3 "Данный скрипт активирует BBR3 нового ядра XANMOD"
print_message 2 "================================================================="

# Пауза на 4 секунды
sleep 4

# Выполнить команду depmod -a
depmod -a

print_message 3 "Применяем изменения"
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
echo net.ipv4.tcp_congestion_control=bbr | tee -a /etc/sysctl.conf
echo net.core.default_qdisc=fq | tee -a /etc/sysctl.conf

print_message 3 "Перезагружаем сеть"
# Применить изменения в sysctl
sysctl -p

print_message 3 "Выводим данные модуля BBR"
# Проверить информацию о модуле tcp_bbr
modinfo tcp_bbr
