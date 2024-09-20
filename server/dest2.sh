#!/bin/bash

# Проверяем наличие Python 3
if ! command -v python3 &> /dev/null; then
    # Определяем систему пакетного менеджера и устанавливаем Python 3
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -y > /dev/null 2>&1
        sudo apt-get install -y python3 python3-pip > /dev/null 2>&1
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3 python3-pip > /dev/null 2>&1
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y python3 python3-pip > /dev/null 2>&1
    else
        echo "Не удалось определить пакетный менеджер. Установите Python 3 вручную."
        exit 1
    fi

    # Проверяем, установился ли Python 3
    if ! command -v python3 &> /dev/null; then
        echo "Не удалось установить Python 3 автоматически. Установите его вручную и повторите попытку."
        exit 1
    fi
fi

# Проверяем и устанавливаем необходимые библиотеки
PYTHON_PACKAGES=("rich" "requests")
for package in "${PYTHON_PACKAGES[@]}"; do
    if ! python3 -c "import $package" &> /dev/null; then
        pip3 install $package > /dev/null 2>&1
    fi
done

# Загружаем и запускаем Python-скрипт
python3 <(wget -qO- https://dignezzz.github.io/server/dest.py) "$@"
