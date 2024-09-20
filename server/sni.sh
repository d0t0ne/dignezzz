#!/bin/bash


declare -A MESSAGES_EN=(
    ["select_language"]="Select Language:"
    ["option1"]="1) English (default)"
    ["option2"]="2) Русский"
    ["invalid_option"]="Invalid option. Please try again."
    ["update_python"]="Installing Python 3 and required packages..."
    ["package_manager_fail"]="Failed to determine package manager. Please install Python 3 manually."
    ["install_fail"]="Failed to install Python 3 automatically. Please install it manually and try again."
    ["default_lang"]="Defaulting to English."
    ["usage"]="Usage: script.py <domain>"
    ["missing_packages"]="The following Python packages are missing: "
    ["installing_packages"]="Installing missing Python packages..."
)

declare -A MESSAGES_RU=(
    ["select_language"]="Выберите язык:"
    ["option1"]="1) Английский (по умолчанию)"
    ["option2"]="2) Русский"
    ["invalid_option"]="Неверный выбор. Пожалуйста, попробуйте снова."
    ["update_python"]="Устанавливаем Python 3 и необходимые пакеты..."
    ["package_manager_fail"]="Не удалось определить пакетный менеджер. Установите Python 3 вручную."
    ["install_fail"]="Не удалось установить Python 3 автоматически. Установите его вручную и повторите попытку."
    ["default_lang"]="По умолчанию выбран Английский."
    ["usage"]="Использование: script.py <домен>"
    ["missing_packages"]="Отсутствуют следующие Python-библиотеки: "
    ["installing_packages"]="Устанавливаем отсутствующие Python-библиотеки..."
)


LANG_CHOICE=1

print_message() {
    local key=$1
    if [ "$LANG_CHOICE" = "1" ]; then
        echo -e "${MESSAGES_EN[$key]}"
    else
        echo -e "${MESSAGES_RU[$key]}"
    fi
}

choose_language() {
    while true; do
        echo -e "${MESSAGES_EN["select_language"]}"
        echo -e "${MESSAGES_EN["option1"]}"
        echo -e "${MESSAGES_EN["option2"]}"
        read -p "Enter your choice [1-2]: " input

        case $input in
            1)
                LANG_CHOICE=1
                break
                ;;
            2)
                LANG_CHOICE=2
                break
                ;;
            *)
                print_message "invalid_option"
                ;;
        esac
    done
    echo "" 
}

install_python_and_packages() {
    print_message "update_python"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -y > /dev/null 2>&1
        sudo apt-get install -y python3 python3-pip > /dev/null 2>&1
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3 python3-pip > /dev/null 2>&1
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y python3 python3-pip > /dev/null 2>&1
    else
        print_message "package_manager_fail"
        exit 1
    fi

    if ! command -v python3 &> /dev/null; then
        print_message "install_fail"
        exit 1
    fi
}

check_and_install_packages() {
    required_packages=("sys" "subprocess" "requests" "time" "threading" "socket" "shutil" "json" "rich")
    missing_packages=()

    for package in "${required_packages[@]}"; do
        if ! python3 -c "import $package" &> /dev/null; then
            missing_packages+=("$package")
        fi
    done

    if [ ${#missing_packages[@]} -ne 0 ]; then
        print_message "missing_packages"
        echo "${missing_packages[@]}"
        print_message "installing_packages"
        for package in "${missing_packages[@]}"; do
            pip3 install "$package" > /dev/null 2>&1
        done
    fi
}

run_python_script() {
    if [ "$LANG_CHOICE" = "1" ]; then
        SCRIPT_URL="https://dignezzz.github.io/server/sni.py"
    else
        SCRIPT_URL="https://dignezzz.github.io/server/sni_ru.py"
    fi
    python3 <(wget -qO- "$SCRIPT_URL") "$@"
}


choose_language


if ! command -v python3 &> /dev/null; then
    install_python_and_packages
fi


check_and_install_packages

clear

run_python_script "$@"
