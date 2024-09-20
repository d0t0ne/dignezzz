#!/bin/bash
clear

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

trap "echo -e '\n${RED}Script interrupted by user.${NC}' && exit 1" SIGINT

check_dependencies() {
    dependencies=("wget" "sudo")
    missing=()
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}The following dependencies are missing:${NC} ${missing[@]}"
        echo -e "${YELLOW}Please install them manually and re-run the script.${NC}"
        exit 1
    fi
}

check_dependencies

declare -A MESSAGES_EN=(
    ["select_language"]="Select Language:"
    ["option1"]="1) English (default)"
    ["option2"]="2) Русский"
    ["invalid_option"]="Invalid option. Continuing with English."
    ["update_python"]="Installing Python 3 and required packages..."
    ["package_manager_fail"]="Failed to determine package manager. Please install Python 3 manually."
    ["install_fail"]="Failed to install Python 3 automatically. Please install it manually and try again."
    ["default_lang"]="Defaulting to English."
    ["usage"]="Usage: script.py <domain>"
    ["missing_packages"]="The following Python packages are missing: "
    ["installing_packages"]="Installing missing Python packages..."
    ["wget_missing"]="wget is not installed. Please install wget and try again."
    ["install_pip"]="Installing pip3 using ensurepip..."
    ["install_pip_fail"]="Failed to install pip3. Plz, install manually, or try to restart this script"
)

declare -A MESSAGES_RU=(
    ["select_language"]="Выберите язык:"
    ["option1"]="1) Английский (по умолчанию)"
    ["option2"]="2) Русский"
    ["invalid_option"]="Неверный выбор. Продолжаем на Английском."
    ["update_python"]="Устанавливаем Python 3 и необходимые пакеты..."
    ["package_manager_fail"]="Не удалось определить пакетный менеджер. Установите Python 3 вручную."
    ["install_fail"]="Не удалось установить Python 3 автоматически. Установите его вручную и повторите попытку."
    ["default_lang"]="По умолчанию выбран Английский."
    ["usage"]="Использование: script.py <домен>"
    ["missing_packages"]="Отсутствуют следующие Python-библиотеки: "
    ["installing_packages"]="Устанавливаем отсутствующие Python-библиотеки..."
    ["wget_missing"]="wget не установлен. Пожалуйста, установите wget и попробуйте снова."
    ["install_pip"]="Устанавливаем pip3 с помощью ensurepip..."
    ["install_pip_fail"]="Не удалось установить pip3. Установите вручную, или попробуйте перезапустить этот скрипт"
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
    echo -e "${BLUE}${MESSAGES_EN["select_language"]}${NC}"
    echo -e "${GREEN}${MESSAGES_EN["option1"]}${NC}"
    echo -e "${GREEN}${MESSAGES_EN["option2"]}${NC}"
    read -p "$(echo -e "${YELLOW}Enter your choice [1-2]: ${NC}")" input

    case $input in
        1)
            LANG_CHOICE=1
            ;;
        2)
            LANG_CHOICE=2
            ;;
        "")
            LANG_CHOICE=1
            print_message "default_lang"
            ;;
        *)
            print_message "invalid_option"
            ;;
    esac
    echo ""
}

install_pip3() {
    print_message "install_pip"
    python3 -m ensurepip --upgrade &> /dev/null
    if ! command -v pip3 &> /dev/null; then
        wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py &> /dev/null
        python3 /tmp/get-pip.py &> /dev/null
        rm /tmp/get-pip.py
    fi

    if ! command -v pip3 &> /dev/null; then
        print_message "install_pip_fail"
        exit 1
    fi
}

install_python_and_packages() {
    print_message "update_python"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -y &> /dev/null
        sudo apt-get install -y python3 python3-pip &> /dev/null
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3 python3-pip &> /dev/null
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y python3 python3-pip &> /dev/null
    else
        print_message "package_manager_fail"
        exit 1
    fi

    if ! command -v python3 &> /dev/null; then
        print_message "install_fail"
        exit 1
    fi

    if ! command -v pip3 &> /dev/null; then
        install_pip3
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
        echo -e "${YELLOW}${missing_packages[@]}${NC}"
        print_message "installing_packages"
        for package in "${missing_packages[@]}"; do
            pip3 install "$package" &> /dev/null
            if [ $? -ne 0 ]; then
                echo -e "${RED}Failed to install package: $package${NC}"
            fi
        done
    fi
}

run_python_script() {
    if [ "$LANG_CHOICE" = "1" ]; then
        SCRIPT_URL="https://dignezzz.github.io/server/sni.py"
    else
        SCRIPT_URL="https://dignezzz.github.io/server/sni_ru.py"
    fi

    if ! command -v wget &> /dev/null; then
        print_message "wget_missing"
        exit 1
    fi

    python3 <(wget -qO- "$SCRIPT_URL") "$@"
}

choose_language

if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
    install_python_and_packages
fi

check_and_install_packages

run_python_script "$@"
