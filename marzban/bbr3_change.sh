#!/bin/bash

# Очистка экрана
clear

# Вывод заголовка
tput bold
tput setaf 2
tput setaf 3
echo "Данный скрипт устанавливает ядро с поддержкой BBR3"
tput setaf 2
echo "================================================================="
tput sgr0

# Пауза на 4 секунды
sleep 4

tput setaf 3
echo "Определяем доступную версию ядра"
tput sgr0

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
    tput setaf 3
    echo "CPU поддерживается x86-64-v$level"
    tput sgr0

    tput setaf 3
    echo "Скачиваем ключи репозитория"
    tput sgr0
    run_command "wget -qO - https://gitlab.com/afrd.gpg | sudo gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes"

    tput setaf 3
    echo "Добавляем репозиторий"
    tput sgr0
    run_command "echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | sudo tee /etc/apt/sources.list.d/xanmod-release.list"

    # Выполнить соответствующее действие в зависимости от уровня
    if [ $level -eq 1 ]; then
        tput setaf 3
        echo "Устанавливаем ядро, не закрывайте окно"
        tput sgr0
        run_command "sudo apt update && sudo apt install -y linux-xanmod-x64v1"
    elif [ $level -eq 2 ]; then
        tput setaf 3
        echo "Устанавливаем ядро, не закрывайте окно"
        tput sgr0
        run_command "sudo apt update && sudo apt install -y linux-xanmod-x64v2"
    elif [ $level -eq 3 ]; then
        tput setaf 3
        echo "Устанавливаем ядро, не закрывайте окно"
        tput sgr0
        run_command "sudo apt update && sudo apt install -y linux-xanmod-x64v3"
    elif [ $level -eq 4 ]; then
        tput setaf 3
        echo "Устанавливаем ядро, не закрывайте окно"
        tput sgr0
        run_command "sudo apt update && sudo apt install -y linux-xanmod-x64v4"
    fi

    # Перезагрузка сервера
    tput setaf 3
    echo "Установка успешно завершена, теперь Вы можете перезагрузить сервер командой reboot"
    tput sgr0
    echo "Не забывайте, что после перезагрузки необходимо выполнить вторую часть скрипта"
else
    echo "Неподдерживаемый уровень"
fi
