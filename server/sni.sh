#!/bin/bash
clear
print_message() {
    local message_key=$1
    if [ "$LANG_CHOICE" = "1" ]; then
        echo -e "${MESSAGES_EN[$message_key]}"
    else
        echo -e "${MESSAGES_RU[$message_key]}"
    fi
}

declare -A MESSAGES_EN
declare -A MESSAGES_RU


MESSAGES_EN=(
    ["select_language"]="Select Language / Выберите язык:"
    ["option1"]="1) English"
    ["option2"]="2) Русский"
    ["invalid_option"]="Invalid option. Please try again."
    ["update_python"]="Installing Python 3 and pip..."
    ["package_manager_fail"]="Failed to determine package manager. Please install Python 3 manually."
    ["install_fail"]="Failed to install Python 3 automatically. Please install it manually and try again."
)

MESSAGES_RU=(
    ["select_language"]="Выберите язык / Select Language:"
    ["option1"]="1) Английский"
    ["option2"]="2) Русский"
    ["invalid_option"]="Неверный выбор. Пожалуйста, попробуйте снова."
    ["update_python"]="Устанавливаем Python 3 и pip..."
    ["package_manager_fail"]="Не удалось определить пакетный менеджер. Установите Python 3 вручную."
    ["install_fail"]="Не удалось установить Python 3 автоматически. Установите его вручную и повторите попытку."
)

choose_language() {
    while true; do
        print_message "select_language"
        print_message "option1"
        print_message "option2"
        read -rp ">> " lang
        lang=${lang:-1} 
        case $lang in
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
}

choose_language


if ! command -v python3 &> /dev/null; then
    print_message "update_python"
    # Определяем систему пакетного менеджера и устанавливаем Python 3
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
fi

PYTHON_PACKAGES=("rich" "requests")
for package in "${PYTHON_PACKAGES[@]}"; do
    if ! python3 -c "import $package" &> /dev/null; then
        pip3 install "$package" > /dev/null 2>&1
    fi
done

if [ "$LANG_CHOICE" = "1" ]; then
    SCRIPT_URL="https://dignezzz.github.io/server/sni.py"
else
    SCRIPT_URL="https://dignezzz.github.io/server/sni_ru.py"
fi

python3 <(wget -qO- "$SCRIPT_URL") "$@"
