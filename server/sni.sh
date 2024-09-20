#!/bin/bash
clear
declare -A MESSAGES_EN=(
    ["select_language"]="Select Language:"
    ["option1"]="1) English (default)"
    ["option2"]="2) Русский"
    ["invalid_option"]="Invalid option. Please try again."
    ["update_python"]="Installing Python 3 and required packages..."
    ["package_manager_fail"]="Failed to determine package manager. Please install Python 3 manually."
    ["install_fail"]="Failed to install Python 3 automatically. Please install it manually and try again."
    ["default_lang"]="No input detected. Defaulting to English."
    ["choose_language_timeout"]="No input detected. Defaulting to English."
    ["timeout_message"]="You have 5 seconds to choose a language. Default is English."
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
    ["default_lang"]="Ввод не получен. По умолчанию выбран Английский."
    ["choose_language_timeout"]="Ввод не получен. По умолчанию выбран Английский."
    ["timeout_message"]="У вас есть 5 секунд для выбора языка. По умолчанию выбран Английский."
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

choose_language_with_timer() {
    echo -e "${MESSAGES_EN["select_language"]}"
    echo -e "${MESSAGES_EN["option1"]}"
    echo -e "${MESSAGES_EN["option2"]}"
    echo "${MESSAGES_EN["timeout_message"]}"

    countdown() {
        for i in {5..1}; do
            echo -ne "Time remaining: $i seconds\r"
            sleep 1
        done
    }

    countdown &
    COUNTDOWN_PID=$!


    read -t5 -p "Enter your choice [1-2]: " input


    kill $COUNTDOWN_PID 2>/dev/null
    echo "" 

    if [ $? -gt 128 ]; then

        LANG_CHOICE=1
        print_message "default_lang"
    else
        case $input in
            1)
                LANG_CHOICE=1
                ;;
            2)
                LANG_CHOICE=2
                ;;
            *)
                print_message "invalid_option"
                LANG_CHOICE=1
                ;;
        esac
    fi
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

choose_language_with_timer

if ! command -v python3 &> /dev/null; then
    install_python_and_packages
fi

check_and_install_packages
run_python_script "$@"
