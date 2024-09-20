#!/bin/bash

# Проверяем наличие Python 3
if ! command -v python3 &> /dev/null; then
    echo "Python 3 не установлен. Установите Python 3 и попробуйте снова."
    exit 1
fi

# Проверяем и устанавливаем необходимые библиотеки
PYTHON_PACKAGES=("rich" "requests")
for package in "${PYTHON_PACKAGES[@]}"; do
    if ! python3 -c "import $package" &> /dev/null; then
        echo "Устанавливаю пакет $package..."
        pip3 install $package
    fi
done

# Загружаем и запускаем Python-скрипт
python3 <(wget -qO- https://dignezzz.github.io/server/dest.py) "$@"
