#!/bin/bash
set -e

# Цвета (оптимизировано)
red="\033[31m"
green="\033[32m"
yellow="\033[33m"
blue="\033[34m"
reset="\033[0m"

# Функции вывода
print() { printf "${blue}%s${reset}\n" "$1"; }
error() { printf "${red}[Ошибка] %s${reset}\n" "$1"; }
success() { printf "${green}[Успех] %s${reset}\n" "$1"; }
input() {
    local __resultvar=$2
    read -p "$(printf "${yellow}%s: ${reset}" "$1")" __temp
    eval "$__resultvar=\"\$__temp\""
}
input_secure() {
    local __resultvar=$2
    read -s -p "$(printf "${yellow}%s: ${reset}" "$1")" __temp
    echo
    eval "$__resultvar=\"\$__temp\""
}
confirm() {
    read -n1 -s -r -p "$(printf "\n${yellow}Нажмите любую клавишу, чтобы продолжить...${reset}")"
    echo
}

check_success() {
    if [ $? -eq 0 ]; then
        success "$1"
    else
        error "$2"
        exit 1
    fi
}

# Проверка запуска от root
if [ "$EUID" -ne 0 ]; then
    error "Пожалуйста, запустите скрипт с правами root."
    exit 1
fi

# Функция установки необходимых пакетов
install_dependencies() {
    print "Обновление системы..."
    apt update -y > /dev/null 2>&1
    check_success "Система успешно обновлена." "Не удалось обновить систему."

    print "Установка SQLite3..."
    apt install -y sqlite3 > /dev/null 2>&1
    check_success "SQLite3 успешно установлен." "Не удалось установить SQLite3."
}

# Функция получения пользовательского ввода
get_user_input() {
    default_docker_compose_path="/opt/marzban/docker-compose.yml"
    default_env_file_path="/opt/marzban/.env"

    while true; do
        input_secure "Введите пароль MySQL root" DB_PASSWORD
        if [ -z "$DB_PASSWORD" ]; then
            error "Пароль не может быть пустым."
        else
            break
        fi
    done

    while true; do
        input "Введите путь к docker-compose.yml [${default_docker_compose_path}]" DOCKER_COMPOSE_PATH
        DOCKER_COMPOSE_PATH=${DOCKER_COMPOSE_PATH:-$default_docker_compose_path}
        if [[ ! -f $DOCKER_COMPOSE_PATH ]]; then
            error "Файл $DOCKER_COMPOSE_PATH не существует."
        else
            break
        fi
    done

    while true; do
        input "Введите путь к файлу .env [${default_env_file_path}]" ENV_FILE_PATH
        ENV_FILE_PATH=${ENV_FILE_PATH:-$default_env_file_path}
        if [[ ! -f $ENV_FILE_PATH ]]; then
            error "Файл $ENV_FILE_PATH не существует."
        else
            break
        fi
    done

    while true; do
        input "Хотите установить phpMyAdmin? (yes/no) [yes]" INSTALL_PHPMYADMIN
        INSTALL_PHPMYADMIN=${INSTALL_PHPMYADMIN:-yes}

        if [ "$INSTALL_PHPMYADMIN" = "yes" ]; then
            while true; do
                input "Введите порт для phpMyAdmin [8010]" PHPMYADMIN_PORT
                PHPMYADMIN_PORT=${PHPMYADMIN_PORT:-8010}

                if ! [[ "$PHPMYADMIN_PORT" =~ ^[0-9]+$ ]]; then
                    error "Недействительный порт."
                    continue
                fi

                if lsof -i :$PHPMYADMIN_PORT > /dev/null 2>&1; then
                    error "Порт $PHPMYADMIN_PORT уже используется."
                    continue
                fi

                break
            done
            break
        elif [ "$INSTALL_PHPMYADMIN" = "no" ]; then
            break
        else
            error "Пожалуйста, введите 'yes' или 'no'."
        fi
    done
}

# Функция резервного копирования
backup_files() {
    local timestamp=$(date +%Y%m%d_%H%M%S)

    cp "$ENV_FILE_PATH" "${ENV_FILE_PATH}_$timestamp.bak"
    check_success "Файл .env сохранен." "Не удалось сохранить файл .env."

    cp "$DOCKER_COMPOSE_PATH" "${DOCKER_COMPOSE_PATH}_$timestamp.bak"
    check_success "Файл docker-compose.yml сохранен." "Не удалось сохранить файл docker-compose.yml."

    if [ -f /var/lib/marzban/db.sqlite3 ]; then
        cp /var/lib/marzban/db.sqlite3 /var/lib/marzban/db.sqlite3_$timestamp.bak
        check_success "Файл db.sqlite3 сохранен." "Не удалось сохранить файл db.sqlite3."
    else
        error "Файл db.sqlite3 не найден, пропуск."
    fi
}

# Функция обновления до MariaDB
upgrade_to_mariadb() {
    architecture=$(uname -m)
    case "$architecture" in
        "arm64"|"aarch64")
            PHPMYADMIN_IMAGE="arm64v8/phpmyadmin:latest"
            ;;
        "x86_64")
            PHPMYADMIN_IMAGE="phpmyadmin/phpmyadmin:latest"
            ;;
        *)
            error "Неподдерживаемая архитектура: $architecture"
            exit 1
            ;;
    esac

    cat <<EOF > "$DOCKER_COMPOSE_PATH"
services:
  marzban:
    image: gozargah/marzban:latest
    restart: always
    env_file: .env
    network_mode: host
    volumes:
      - /var/lib/marzban:/var/lib/marzban
    depends_on:
      mariadb:
        condition: service_healthy

  mariadb:
    image: mariadb:lts
    env_file: .env
    network_mode: host
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_ROOT_HOST: '%'
      MYSQL_DATABASE: marzban
      MYSQL_USER: marzban
      MYSQL_PASSWORD: ${DB_PASSWORD}
    command:
      - --bind-address=127.0.0.1
      - --character_set_server=utf8mb4
      - --collation_server=utf8mb4_unicode_ci
      - --host-cache-size=0
      - --innodb-open-files=1024
      - --innodb-buffer-pool-size=268435456
      - --binlog_expire_logs_seconds=5184000 # 60 days
    volumes:
      - /var/lib/marzban/mysql:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      start_period: 10s
      start_interval: 3s
      interval: 10s
      timeout: 5s
      retries: 3
EOF

    if [ "$INSTALL_PHPMYADMIN" = "yes" ]; then
        cat <<EOF >> "$DOCKER_COMPOSE_PATH"

  phpmyadmin:
    image: $PHPMYADMIN_IMAGE
    restart: always
    env_file: .env
    network_mode: host
    environment:
      PMA_HOST: 127.0.0.1
      APACHE_PORT: ${PHPMYADMIN_PORT}
      UPLOAD_LIMIT: 1024M
    depends_on:
      - mariadb
EOF
    fi

    sed -i.bak '/^SQLALCHEMY_DATABASE_URL/ s/^/#/' "$ENV_FILE_PATH"
    sed -i '/^MYSQL_ROOT_PASSWORD/ s/^/#/' "$ENV_FILE_PATH"

    {
        echo "SQLALCHEMY_DATABASE_URL=\"mysql+pymysql://root:${DB_PASSWORD}@127.0.0.1/marzban\""
        echo "MYSQL_ROOT_PASSWORD=${DB_PASSWORD}"
    } >> "$ENV_FILE_PATH"

    docker compose -f "$DOCKER_COMPOSE_PATH" down || true

    docker compose -f "$DOCKER_COMPOSE_PATH" up -d mariadb
    check_success "MariaDB запущен." "Не удалось запустить MariaDB."

    if [ "$INSTALL_PHPMYADMIN" = "yes" ]; then
        docker compose -f "$DOCKER_COMPOSE_PATH" up -d phpmyadmin
        check_success "phpMyAdmin запущен." "Не удалось запустить phpMyAdmin."
    fi

    docker compose -f "$DOCKER_COMPOSE_PATH" up -d marzban
    check_success "Marzban запущен." "Не удалось запустить Marzban."
}

migrate_database() {
    if [ ! -f /var/lib/marzban/db.sqlite3 ]; then
        error "Файл db.sqlite3 не найден."
        exit 1
    fi

    # Создание дампа SQLite
    sqlite3 /var/lib/marzban/db.sqlite3 '.dump --data-only' | sed "s/INSERT INTO \([^ ]*\)/REPLACE INTO \`\1\`/g" > /tmp/dump.sql
    check_success "Дамп SQLite создан." "Не удалось создать дамп SQLite."

    # Проверка статуса контейнера MariaDB
    print "Проверка запуска контейнера MariaDB..."
    until docker compose -f "$DOCKER_COMPOSE_PATH" ps mariadb | grep -q "Up"; do
        print "Ожидание запуска контейнера MariaDB..."
        sleep 3
    done
    success "Контейнер MariaDB успешно запущен."

    # Копирование дампа в контейнер MariaDB
    docker compose -f "$DOCKER_COMPOSE_PATH" cp /tmp/dump.sql mariadb:/dump.sql
    check_success "Дамп скопирован в контейнер MariaDB." "Не удалось скопировать дамп в контейнер MariaDB."

    # Выполнение команды для восстановления дампа в MariaDB
    docker compose -f "$DOCKER_COMPOSE_PATH" exec mariadb mysql -u root -p"${DB_PASSWORD}" -h 127.0.0.1 marzban -e "SET FOREIGN_KEY_CHECKS = 0; SET NAMES utf8mb4; SOURCE /dump.sql;"
    check_success "Данные перенесены в MariaDB." "Не удалось перенести данные в MariaDB."

    # Удаление временного дампа
    rm /tmp/dump.sql

    # Перезапуск сервиса Marzban после миграции
    docker compose -f "$DOCKER_COMPOSE_PATH" restart marzban
    check_success "Marzban перезапущен." "Не удалось перезапустить Marzban."

    if [ "$INSTALL_PHPMYADMIN" = "yes" ]; then
        print "Marzban работает с MariaDB и phpMyAdmin."
        success "Доступ к phpMyAdmin: http://<IP>:${PHPMYADMIN_PORT}"
        success "Логин: root"
        success "Пароль: ваш указанный пароль"
    else
        print "Marzban работает с MariaDB."
    fi

    success "Миграция завершена."
    confirm
}

# Основное меню
main_menu() {
    while true; do
        print ""
        print "Скрипт миграции Marzban с SQLite3 на MariaDB"
        print ""
        print "1. Начать миграцию"
        print "0. Выход"
        print ""
        input "Введите ваш выбор" choice
        case $choice in
            1)
                install_dependencies
                get_user_input
                backup_files
                upgrade_to_mariadb
                migrate_database
                ;;
            0)
                print "Выход..."
                exit 0
                ;;
            *)
                error "Недопустимый выбор."
                ;;
        esac
    done
}

# Запуск скрипта
clear
main_menu
