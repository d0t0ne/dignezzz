#!/usr/bin/env python

import subprocess
import re

# Константы
TPUT = "tput"
SETAF = "setaf"
BOLD = "bold"
COLOR_GREEN = "2"
COLOR_YELLOW = "3"
CLEAR_SCREEN = "clear"

# Функция для вывода сообщений
def print_message(message, color):
    command = f"{TPUT} {SETAF} {color}"
    subprocess.run(command, shell=True)
    print(message)
    subprocess.run(f"{TPUT} sgr0", shell=True)

# Функция для выполнения команды и обработки вывода
def run_command(command):
    try:
        result = subprocess.check_output(command, shell=True, text=True)
    except subprocess.CalledProcessError as e:
        print_message(f"Ошибка выполнения команды '{command}': {e.output}", COLOR_YELLOW)
        exit(1)
    return result

# Начинаем с чисого листа
subprocess.run([CLEAR_SCREEN], shell=True)

print('''
BBBB  Y   Y     DDD  III  GGG  N   N EEEE ZZZZZ ZZZZZ ZZZZZ 
B   B  Y Y      D  D  I  G     NN  N E       Z     Z     Z  
BBBB    Y       D  D  I  G  GG N N N EEE    Z     Z     Z   
B   B   Y       D  D  I  G   G N  NN E     Z     Z     Z    
BBBB    Y       DDD  III  GGG  N   N EEEE ZZZZZ ZZZZZ ZZZZZ 

Данный скрипт установит  XanMod + BBR3
''')


# Ждем пару сек, что бы пользователь прочитал
subprocess.run("sleep 4", shell=True)
print_message("Определяем доступную версию ядра", COLOR_YELLOW)

# Получение информации о CPU
try:
    cpu_info = run_command("cat /proc/cpuinfo")
except FileNotFoundError:
    print_message("Файл /proc/cpuinfo не найден", COLOR_YELLOW)
    exit(1)

# Определение уровня поддержки
level = None
if re.search(r'lm|cmov|cx8|fpu|fxsr|mmx|syscall|sse2', cpu_info):
    level = 1
if level and re.search(r'cx16|lahf|popcnt|sse4_1|sse4_2|ssse3', cpu_info):
    level = 2
if level and re.search(r'avx|avx2|bmi1|bmi2|f16c|fma|abm|movbe|xsave', cpu_info):
    level = 3
if level and re.search(r'avx512f|avx512bw|avx512cd|avx512dq|avx512vl', cpu_info):
    level = 4

if level:
    print_message(f"CPU поддерживается x86-64-v{level}", COLOR_YELLOW)
    print_message("Скачиваем ключи репозитория", COLOR_YELLOW)
    run_command("wget -qO - https://gitlab.com/afrd.gpg | sudo gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes")
    print_message("Добавляем репозиторий", COLOR_YELLOW)
    run_command("echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | sudo tee /etc/apt/sources.list.d/xanmod-release.list")

    # Выполнить соответствующее действие в зависимости от уровня
    if level == 1:
        print_message("Устанавливаем ядро, не закрывайте окно", COLOR_YELLOW)
        run_command("sudo apt update && sudo apt install -y linux-xanmod-x64v1")
    elif level == 2:
        print_message("Устанавливаем ядро, не закрывайте окно", COLOR_YELLOW)
        run_command("sudo apt update && sudo apt install -y linux-xanmod-x64v2")
    elif level == 3:
        print_message("Устанавливаем ядро, не закрывайте окно", COLOR_YELLOW)
        run_command("sudo apt update && sudo apt install -y linux-xanmod-x64v3")
    elif level == 4:
        print_message("Устанавливаем ядро, не закрывайте окно", COLOR_YELLOW)
        run_command("sudo apt update && sudo apt install -y linux-xanmod-x64v4")

    # Перезагрузка сервера
    print_message("Установка успешно завершена, теперь Вы можете перезагрузить сервер командой reboot", COLOR_YELLOW)
    print_message("Не забывайте, что после перезагрузки необходимо выполнить вторую часть скрипта", COLOR_YELLOW)
else:
    print_message("Неподдерживаемый уровень", COLOR_YELLOW)
