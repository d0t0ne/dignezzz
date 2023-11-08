#!/usr/bin/env python
import subprocess

# Стандартные значения
ssh_port = "22"
service_port = "62050"
xray_api_port = "62051"
# Начинаем с чисого листа
subprocess.run(["clear"])
# Вывод заголовка
subprocess.run(["tput", "bold"])
subprocess.run(["tput", "setaf", "2"])
print(f"=================================================================")
print(f"=====================Marzban-Node UFW enable=====================")
print(f"=================================================================")
subprocess.run(["tput", "setaf", "3"])
print(f"Данный скрипт закроет все порты на узле, с помошью UFW")
print(f"за исключением тех портов, что использует панель Marzban")
subprocess.run(["tput", "setaf", "1"])
print(f"!Marzban-Node должен быть установлен!")
subprocess.run(["tput", "setaf", "2"])
print(f"=================================================================")
subprocess.run(["tput", "sgr0"])
# Ждем пару сек, что бы пользователь прочитал
subprocess.run(["sleep", "4"])

subprocess.run(["tput", "setaf", "3"])
# Ввод MASTER_IP
master_ip = input("Введите MASTER_IP: ")
subprocess.run(["tput", "setaf", "4"])


subprocess.run(["tput", "setaf", "3"])
print(f"Введите через запятую используемые порты протоколов:")
subprocess.run(["tput", "sgr0"])
arr = list([int(i) for i in input().split(',')])


subprocess.run(["tput", "setaf", "3"])
print(f"Приступаем к установке UFW:")
subprocess.run(["tput", "setaf", "4"])

subprocess.run(["apt", "install", "-y", "ufw"])
subprocess.run(["ufw", "disable"])

subprocess.run(["tput", "setaf", "3"])
print(f"Сбрасываем старые правила UFW:")
subprocess.run(["tput", "setaf", "4"])
subprocess.run("echo y | sudo ufw reset", shell=True)

    
subprocess.run(["tput", "setaf", "3"])
print(f"Добавляем новые правила:")
subprocess.run(["tput", "setaf", "4"])

subprocess.run(["ufw", "default", "deny", "incoming"])
subprocess.run(["ufw", "default", "allow", "outgoing"])
subprocess.run(["ufw", "allow", ssh_port])
subprocess.run(f"ufw allow from {master_ip} to any port 62050", shell=True)
subprocess.run(f"ufw allow from {master_ip} to any port 62051", shell=True)
for port in arr:
    subprocess.run(["ufw", "allow", str(port)])    
subprocess.run(["tput", "setaf", "3"])
print(f"Активируем новые правила UFW:")
subprocess.run(["tput", "setaf", "4"])

subprocess.run("echo y | sudo ufw enable", shell=True)
subprocess.run(["ufw", "reload"])

subprocess.run(["tput", "setaf", "3"])
print(f"Все готово! Теперь Вы можете добавить другие свои порты вручную")
print(f"с помощью UFW ALLOW НУЖНЫЙ_ПОРТ")
subprocess.run(["tput", "sgr0"])
subprocess.run(["sleep", "1"])

