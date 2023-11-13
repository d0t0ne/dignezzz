#!/bin/bash

# Очистка экрана
clear

# Вывод заголовка
echo -e "\e[1m\e[33mДанный скрипт устанавливает ядро с поддержкой BBR3\n=================================================================\e[0m"

# Пауза на 4 секунды
sleep 4

echo -e "\e[33mОпределяем доступную версию ядра\e[0m"

# Функция для выполнения команды и обработки вывода
run_command() {
    result=$(eval $1)
    if [ $? -ne 0 ]; then
        echo "Ошибка выполнения команды: $result"
        exit 1
    fi
    echo $result
}

# Получение информации о CPU
cpu_info=$(run_command "cat /proc/cpuinfo")

# Определение уровня поддержки
level=0
if [[ $cpu_info =~ lm|cmov|cx8|fpu|fxsr|mmx|syscall|sse2 ]]; then
    level=1
fi
if [[ $level -eq 1 && $cpu_info =~ cx16|lahf|popcnt|sse4_1|sse4_2|ssse3 ]]; then
    level=2
fi
if [[ $level -eq 2 && $cpu_info =~ avx|avx2|bmi1|bmi2|f16c|fma|abm|movbe|xsave ]]; then
    level=3
fi
if [[ $level -eq 3 && $cpu_info =~ avx512f|avx512bw|avx512cd|avx512dq|avx512vl ]]; then
    level=4
fi

if [ $level -gt 0 ]; then
    echo -e "\e[33mCPU поддерживается x86-64-v$level\e[0m"
    echo -e "\e[33mСкачиваем ключи репозитория\e[0m"
    run_command "wget -qO - https://gitlab.com/afrd.gpg | sudo gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes"
    echo -e "\e[33mДобавляем репозиторий\e[0m"
    run_command "echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | sudo tee /etc/apt/sources.list.d/xanmod-release.list"

    # Выполнить соответствующее действие в зависимости от уровня
    echo -e "\e[33mУстанавливаем ядро, не закрывайте окно\e[0m"
    run_command "sudo apt update && sudo apt install -y linux-xanmod-x64v$level"

    # Перезагрузка сервера
    echo -e "\e[33mУстановка успешно завершена, теперь Вы можете перезагрузить сервер командой reboot\nНе забывайте, что после перезагрузки необходимо выполнить вторую часть скрипта\e[0m"
else
    echo "Неподдерживаемый уровень"
fi
