#!/bin/bash
set -e

# Цвета
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

# Функция выбора базы данных
select_database() {
    while true; do
        print "Выберите целевую базу данных для миграции:"
        print "1. MariaDB"
        print "2. MySQL 8.3"
        input "Введите номер варианта" DB_CHOICE
        case $DB_CHOICE in
            1)
                DB_ENGINE="mariadb"
                break
                ;;
            2)
                DB_ENGINE="mysql"
                break
                ;;
            *)
                error "Недопустимый выбор. Пожалуйста, выберите 1 или 2."
                ;;
        esac
    done
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
}

# Функция обновления .env для новой базы данных
update_env_file() {
    if [ "$DB_ENGINE" = "mariadb" ]; then
        DB_URL="mysql+pymysql://marzban:${DB_PASSWORD}@127.0.0.1:3306/marzban"
    else
        DB_URL="mysql+pymysql://marzban:${DB_PASSWORD}@127.0.0.1:3306/marzban"
    fi
    sed -i "s|^SQLALCHEMY_DATABASE_URL.*|SQLALCHEMY_DATABASE_URL = \"$DB_URL\"|" "$ENV_FILE_PATH"
    check_success "Конфигурация .env успешно обновлена." "Не удалось обновить файл .env."
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

# Функция настройки docker-compose для MariaDB
setup_mariadb() {
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
    volumes:
      - /var/lib/marzban/mysql:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-u", "marzban", "--password=${DB_PASSWORD}"]
      start_period: 10s
      interval: 5s
      retries: 5
EOF
}

# Функция настройки docker-compose для MySQL 8.3
setup_mysql() {
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
      mysql:
        condition: service_healthy

  mysql:
    image: mysql:8.3
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
      - --mysqlx=OFF
      - --bind-address=127.0.0.1
      - --character_set_server=utf8mb4
      - --collation_server=utf8mb4_unicode_ci
    volumes:
      - /var/lib/marzban/mysql:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-u", "marzban", "--password=${DB_PASSWORD}"]
      start_period: 10s
      interval: 5s
      retries: 5
EOF
}

# Функция миграции базы данных
migrate_database() {
    if [ ! -f /var/lib/marzban/db.sqlite3 ]; then
        error "Файл db.sqlite3 не найден."
        exit 1
    fi

    # Создание дампа только данных из SQLite
    sqlite3 /var/lib/marzban/db.sqlite3 '.dump --data-only' | sed "s/INSERT INTO \([^ ]*\)/REPLACE INTO \`\1\`/g" > /tmp/dump.sql
    check_success "Дамп данных SQLite создан." "Не удалось создать дамп SQLite."

    # Запуск контейнеров
    docker compose -f "$DOCKER_COMPOSE_PATH" down || true
    docker compose -f "$DOCKER_COMPOSE_PATH" up -d $DB_ENGINE marzban

    # Ожидание для создания таблиц в базе данных
    print "Ожидание 10 секунд для создания таблиц в базе данных..."
    sleep 10

    # Проверка создания таблиц
    docker compose -f "$DOCKER_COMPOSE_PATH" cp /tmp/dump.sql $DB_ENGINE:/dump.sql
    docker compose -f "$DOCKER_COMPOSE_PATH" exec $DB_ENGINE mysql -u root -p"${DB_PASSWORD}" -h 127.0.0.1 marzban -e "SET FOREIGN_KEY_CHECKS = 0; SET NAMES utf8mb4; SOURCE /dump.sql;"
    check_success "Данные успешно восстановлены в базе данных." "Не удалось восстановить данные."

    # Удаление временного дампа
    rm /tmp/dump.sql

    # Перезапуск Marzban
    docker compose -f "$DOCKER_COMPOSE_PATH" restart marzban
    check_success "Marzban успешно перезапущен." "Не удалось перезапустить Marzban."

    success "Миграция завершена."
    confirm
}

# Основное меню
main_menu() {
    while true; do
        print ""
        print "Скрипт миграции Marzban с SQLite3 на выбранную базу данных"
        print ""
        print "1. Начать миграцию"
        print "0. Выход"
        print ""
        input "Введите ваш выбор" choice
        case $choice in
            1)
                install_dependencies
                select_database
                get_user_input
                backup_files
                update_env_file
                if [ "$DB_ENGINE" = "mariadb" ]; then
                    setup_mariadb
                else
                    setup_mysql
                fi
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
