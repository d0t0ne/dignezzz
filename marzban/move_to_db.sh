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
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      start_period: 10s
      start_interval: 3s
      interval: 10s
      timeout: 5s
      retries: 3
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
      test: mysqladmin ping -h 127.0.0.1 -u marzban --password=password
      start_period: 5s
      interval: 5s
      timeout: 5s
      retries: 55
EOF
}

# Функция миграции базы данных
migrate_database() {
    if [ ! -f /var/lib/marzban/db.sqlite3 ]; then
        error "Файл db.sqlite3 не найден."
        exit 1
    fi

    # Создание полного дампа SQLite (схема + данные)
    sqlite3 /var/lib/marzban/db.sqlite3 '.dump' > /tmp/dump.sql
    check_success "Дамп SQLite создан." "Не удалось создать дамп SQLite."

    # Проверка статуса контейнера базы данных
    print "Проверка запуска контейнера базы данных..."
    until docker compose -f "$DOCKER_COMPOSE_PATH" ps $DB_ENGINE | grep -q "Up"; do
        print "Ожидание запуска контейнера базы данных..."
        sleep 3
    done
    success "Контейнер базы данных успешно запущен."

    # Копирование дампа в контейнер базы данных
    docker compose -f "$DOCKER_COMPOSE_PATH" cp /tmp/dump.sql $DB_ENGINE:/dump.sql
    check_success "Дамп скопирован в контейнер базы данных." "Не удалось скопировать дамп в контейнер базы данных."

    # Определяем хост для подключения
    if [ "$DB_ENGINE" = "mariadb" ]; then
        DB_HOST="localhost"
        DB_CMD="mariadb"
    else
        DB_HOST="localhost"
        DB_CMD="mysql"
    fi

    # Выполнение команды для восстановления дампа в MariaDB или MySQL
    docker compose -f "$DOCKER_COMPOSE_PATH" exec $DB_ENGINE $DB_CMD -u root -p"${DB_PASSWORD}" -h "$DB_HOST" marzban -e "SET FOREIGN_KEY_CHECKS = 0; SET NAMES utf8mb4; SOURCE /dump.sql;"
    check_success "Данные перенесены в базу данных." "Не удалось перенести данные в базу данных."

    # Удаление временного дампа
    rm /tmp/dump.sql

    # Перезапуск сервиса Marzban после миграции
    docker compose -f "$DOCKER_COMPOSE_PATH" restart marzban
    check_success "Marzban перезапущен." "Не удалось перезапустить Marzban."

    if [ "$INSTALL_PHPMYADMIN" = "yes" ]; then
        print "Marzban работает с базой данных и phpMyAdmin."
        success "Доступ к phpMyAdmin: http://<IP>:${PHPMYADMIN_PORT}"
        success "Логин: root"
        success "Пароль: ваш указанный пароль"
    else
        print "Marzban работает с базой данных."
    fi

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
                if [ "$DB_ENGINE" = "mariadb" ]; then
                    setup_mariadb
                else
                    setup_mysql
                fi
                docker compose -f "$DOCKER_COMPOSE_PATH" down || true
                docker compose -f "$DOCKER_COMPOSE_PATH" up -d $DB_ENGINE
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
