#!/bin/bash

# Очистка экрана
clear
# Системные лимиты - это ограничения, которые операционная система накладывает на различные аспекты системы, такие как максимальное количество открытых файлов или максимальное количество процессов, которые может запустить пользователь.

# Наш скрипт устанавливает эти лимиты в “неограниченное” состояние, что может быть полезно для определенных типов приложений, которые требуют большого количества ресурсов. Однако следует быть осторожным при установке этих лимитов в “неограниченное” состояние, так как это может привести к перерасходу ресурсов.

# Вывод заголовка
echo -e "\e[1m\e[33mОптимизация сервера\e[0m"
echo -e "\e[1m\e[33m
Системные лимиты - это ограничения, которые операционная система накладывает на различные аспекты системы, такие как максимальное количество открытых файлов или максимальное количество процессов, которые может запустить пользователь.
Наш скрипт устанавливает эти лимиты в “неограниченное” состояние, что может быть полезно для определенных типов приложений, которые требуют большого количества ресурсов. Однако следует быть осторожным при установке этих лимитов в “неограниченное” состояние, так как это может привести к перерасходу ресурсов.
После выполнения скрипта вам потребуется перезагрузить систему\e[0m"
# Пауза на 4 секунды
sleep 4

echo -e "\e[33mУдаляем старые значения\e[0m"

# Удаление старых значений системных лимитов
sed -i '/ulimit -c/d' /etc/profile
sed -i '/ulimit -d/d' /etc/profile
sed -i '/ulimit -f/d' /etc/profile
sed -i '/ulimit -i/d' /etc/profile
sed -i '/ulimit -l/d' /etc/profile
sed -i '/ulimit -m/d' /etc/profile
sed -i '/ulimit -n/d' /etc/profile
sed -i '/ulimit -q/d' /etc/profile
sed -i '/ulimit -s/d' /etc/profile
sed -i '/ulimit -t/d' /etc/profile
sed -i '/ulimit -u/d' /etc/profile
sed -i '/ulimit -v/d' /etc/profile
sed -i '/ulimit -x/d' /etc/profile
sed -i '/ulimit -s/d' /etc/profile

echo -e "\e[33mВсе старые значения удалены.\e[0m"

echo -e "\e[33mДобавляем новые значения\e[0m"

# Добавление новых значений системных лимитов
echo "ulimit -c unlimited" | tee -a /etc/profile
echo "ulimit -d unlimited" | tee -a /etc/profile
echo "ulimit -f unlimited" | tee -a /etc/profile
echo "ulimit -i unlimited" | tee -a /etc/profile
echo "ulimit -l unlimited" | tee -a /etc/profile
echo "ulimit -m unlimited" | tee -a /etc/profile
echo "ulimit -n 1048576" | tee -a /etc/profile
echo "ulimit -q unlimited" | tee -a /etc/profile
echo "ulimit -s -H 65536" | tee -a /etc/profile
echo "ulimit -s 32768" | tee -a /etc/profile
echo "ulimit -t unlimited" | tee -a /etc/profile
echo "ulimit -u unlimited" | tee -a /etc/profile
echo "ulimit -v unlimited" | tee -a /etc/profile
echo "ulimit -x unlimited" | tee -a /etc/profile

echo -e "\e[33mВсе новые значения добавлены.\e[0m"

echo -e "\e[33mСистемные лимиты оптимизированны до лучших показателей\e[0m"
