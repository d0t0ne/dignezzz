#!/bin/bash
clear

declare -A MESSAGES_EN=(
    ["select_language"]="Select Language / Выберите язык:"
    ["option1"]="1) English (default)"
    ["option2"]="2) Русский"
    ["invalid_option"]="Invalid option. Please try again."
    ["update_python"]="Installing Python 3 and pip..."
    ["package_manager_fail"]="Failed to determine package manager. Please install Python 3 manually."
    ["install_fail"]="Failed to install Python 3 automatically. Please install it manually and try again."
    ["default_lang"]="No input detected. Defaulting to English."
    ["choose_language_timeout"]="No input detected. Defaulting to English."
    ["timeout_message_en"]="You have 5 seconds to choose a language. Default is English."
    ["timeout_message_ru"]="У вас есть 5 секунд для выбора языка. По умолчанию выбран Английский."
)

declare -A MESSAGES_RU=(
    ["select_language"]="Выберите язык / Select Language:"
    ["option1"]="1) English (default)"
    ["option2"]="2) Русский"
    ["invalid_option"]="Неверный выбор. Пожалуйста, попробуйте снова."
    ["update_python"]="Устанавливаем Python 3 и pip..."
    ["package_manager_fail"]="Не удалось определить пакетный менеджер. Установите Python 3 вручную."
    ["install_fail"]="Не удалось установить Python 3 автоматически. Установите его вручную и повторите попытку."
    ["default_lang"]="Ввод не получен. По умолчанию выбран Английский."
    ["choose_language_timeout"]="Ввод не получен. По умолчанию выбран Английский."
    ["timeout_message_en"]="You have 5 seconds to choose a language. Default is English."
    ["timeout_message_ru"]="У вас есть 5 секунд для выбора языка. По умолчанию выбран Английский."
)

print_message() {
    local key=$1
    if [ "$LANG_CHOICE" = "1" ]; then
        echo -e "${MESSAGES_EN[$key]}"
    else
        echo -e "${MESSAGES_RU[$key]}"
    fi
}

choose_language_with_timer() {
    DEFAULT_LANG_CHOICE=1
    echo -e "${MESSAGES_EN["select_language"]}"
    echo -e "${MESSAGES_EN["option1"]}"
    echo -e "${MESSAGES_EN["option2"]}"
    echo -e "${MESSAGES_RU["select_language"]}"
    echo -e "${MESSAGES_RU["option1"]}"
    echo -e "${MESSAGES_RU["option2"]}"
    echo "${MESSAGES_EN["timeout_message_en"]}"
    echo "${MESSAGES_RU["timeout_message_ru"]}"
    LANG_CHOICE=$DEFAULT_LANG_CHOICE
    for ((i=5; i>0; i--)); do
        echo -ne "Time remaining: $i seconds\r"
        if read -t 1 -n 1 input; then
            case $input in
                1)
                    LANG_CHOICE=1
                    echo ""
                    break
                    ;;
                2)
                    LANG_CHOICE=2
                    echo ""
                    break
                    ;;
                *)
                    echo ""
                    print_message "invalid_option"
                    LANG_CHOICE=$DEFAULT_LANG_CHOICE
                    break
                    ;;
            esac
        fi
    done
    echo ""
    if [ "$LANG_CHOICE" = "$DEFAULT_LANG_CHOICE" ]; then
        print_message "choose_language_timeout"
    fi
}

install_python() {
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

install_packages() {
    PYTHON_PACKAGES=("rich" "requests")
    for package in "${PYTHON_PACKAGES[@]}"; do
        if ! python3 -c "import $package" &> /dev/null; then
            pip3 install "$package" > /dev/null 2>&1
        fi
    done
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
    install_python
fi
install_packages
run_python_script
