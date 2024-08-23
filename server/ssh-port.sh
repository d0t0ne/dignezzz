#!/bin/bash

# Проверка прав администратора
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo "Пожалуйста, запустите скрипт с правами суперпользователя (sudo)."
        exit 1
    fi
}

# Определение ОС и версии
detect_os() {
    os_name=$(lsb_release -is 2>/dev/null || grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    os_version=$(lsb_release -rs 2>/dev/null || grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    echo "Определенная система: $os_name $os_version"
}

# Получение текущего порта
get_current_port() {
    local config_file=$1
    if [ -f "$config_file" ]; then
        grep -Po '(?<=^Port )\d+' "$config_file" || echo "22"
    else
        echo "22"
    fi
}

# Смена порта в конфигурационном файле
change_port_in_config() {
    local config_file=$1
    local port=$2
    if [ -f "$config_file" ]; then
        sed -i "s/^#Port 22/Port $port/" "$config_file"
        sed -i "s/^Port [0-9]\+/Port $port/" "$config_file"
    fi
}

# Перезагрузка SSH службы
reload_ssh_service() {
    if command -v systemctl > /dev/null; then
        systemctl daemon-reload
        systemctl restart ssh || systemctl restart sshd
    else
        service ssh restart || service sshd restart
    fi
}

# Проверка на занятость порта
check_port_availability() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        echo "Ошибка: порт $port уже занят другим процессом."
        exit 1
    fi
}

# Запрос нового порта у пользователя
prompt_for_port() {
    read -p "Введите новый порт для SSH (1-65535): " new_port

    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo "Ошибка: порт должен быть числом в диапазоне от 1 до 65535."
        exit 1
    fi

    check_port_availability "$new_port"
    echo "$new_port"
}

# Смена порта SSH для Ubuntu 24.04
change_port_ubuntu_2404() {
    local current_port=$(get_current_port "/lib/systemd/system/ssh.socket")
    echo "Текущий порт SSH: $current_port"
    
    local new_port=$(prompt_for_port)
    
    sed -i "s/^ListenStream=.*/ListenStream=$new_port/" "/lib/systemd/system/ssh.socket"
    change_port_in_config "/etc/ssh/sshd_config" "$new_port"
    reload_ssh_service
    
    echo "Порт SSH успешно изменен на $new_port."
}

# Смена порта SSH для других версий Ubuntu и других систем
change_port_other_systems() {
    local current_port=$(get_current_port "/etc/ssh/sshd_config")
    echo "Текущий порт SSH: $current_port"
    
    local new_port=$(prompt_for_port)
    
    change_port_in_config "/etc/ssh/sshd_config" "$new_port"
    reload_ssh_service
    
    echo "Порт SSH успешно изменен на $new_port."
}

# Основная функция
main() {
    check_root
    detect_os

    case "$os_name" in
        Ubuntu)
            if [[ "$os_version" == "24.04" ]]; then
                change_port_ubuntu_2404
            else
                change_port_other_systems
            fi
            ;;
        CentOS|Fedora|RHEL|Debian)
            change_port_other_systems
            ;;
        *)
            echo "ОС не поддерживается этим скриптом."
            exit 1
            ;;
    esac

    # Вывод информации о новом подключении
    echo "Теперь вы можете подключиться к серверу с помощью команды:"
    echo "ssh -p $new_port [ваш_пользователь]@[ваш_сервер]"
}

# Запуск основного скрипта
main
