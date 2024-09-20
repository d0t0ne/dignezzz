#!/bin/bash

# Проверяем наличие Python 3
if ! command -v python3 &> /dev/null; then
    echo "Python 3 не установлен. Установите Python 3 и попробуйте снова."
    exit 1
fi

# Проверяем и устанавливаем необходимые библиотеки
PYTHON_PACKAGES=("rich" "requests")
for package in "${PYTHON_PACKAGES[@]}"; do
    if ! python3 -c "import $package" &> /dev/null; then
        echo "Устанавливаю пакет $package..."
        pip3 install $package
    fi
done

# Загружаем и запускаем Python-скрипт
python3 - << 'EOF'
# Ваш Python-скрипт начинается здесь
import sys
import socket
import subprocess
import requests
import json
import time
import threading

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.table import Table
from rich.panel import Panel

console = Console()

# Глобальные результаты
results = {
    "domain": "",
    "tls": False,
    "http2": False,
    "cdn": False,
    "redirect": False,
    "ping": None,
    "rating": 0,
    "cdn_provider": None,
    "negatives": [],
    "positives": [],
}

# Функция для проверки TLS 1.3
def check_tls(domain):
    try:
        proc = subprocess.run(
            ["openssl", "s_client", "-connect", f"{domain}:443", "-tls1_3"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            text=True,
        )
        if "TLSv1.3" in proc.stderr:
            results["tls"] = True
            results["positives"].append("Поддерживается TLS 1.3")
        else:
            proc = subprocess.run(
                ["openssl", "s_client", "-connect", f"{domain}:443"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                text=True,
            )
            protocol_line = next(
                (line for line in proc.stderr.split("\n") if "Protocol  :" in line),
                None,
            )
            if protocol_line:
                tls_version = protocol_line.split(":")[1].strip()
                results["negatives"].append(f"Не поддерживается TLS 1.3 (используется {tls_version})")
            else:
                results["negatives"].append("Не удалось определить используемую версию TLS")
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке TLS: {e}")

# Функция для проверки HTTP/2
def check_http2(domain):
    try:
        proc = subprocess.run(
            ["curl", "-I", "-s", "--http2", f"https://{domain}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            text=True,
        )
        if "HTTP/2" in proc.stdout:
            results["http2"] = True
            results["positives"].append("Поддерживается HTTP/2")
        else:
            results["negatives"].append("Не поддерживается HTTP/2")
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке HTTP/2: {e}")

# Функция для проверки наличия CDN
def check_cdn(domain):
    cdn_providers = {
        "cloudflare": "Cloudflare",
        "akamai": "Akamai",
        "fastly": "Fastly",
        "incapsula": "Imperva Incapsula",
        "sucuri": "Sucuri",
        "stackpath": "StackPath",
        "cdn77": "CDN77",
        "edgecast": "Verizon Edgecast",
        "keycdn": "KeyCDN",
        "azure": "Microsoft Azure CDN",
        "aliyun": "Alibaba Cloud CDN",
        "baidu": "Baidu Cloud CDN",
        "tencent": "Tencent Cloud CDN",
    }
    try:
        response = requests.head(f"https://{domain}", timeout=5)
        headers = response.headers
        header_str = str(headers).lower()
        for key, provider in cdn_providers.items():
            if key in header_str:
                results["cdn"] = True
                results["cdn_provider"] = provider
                results["negatives"].append(f"Использование CDN: {provider}")
                return
        results["positives"].append("CDN не используется")
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке CDN: {e}")

# Функция для проверки переадресации
def check_redirect(domain):
    try:
        response = requests.get(f"https://{domain}", timeout=5, allow_redirects=False)
        if 300 <= response.status_code < 400:
            results["redirect"] = True
            results["negatives"].append(f"Найдена переадресация: {response.headers.get('Location')}")
        else:
            results["positives"].append("Переадресация отсутствует")
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке переадресации: {e}")

# Функция для вычисления среднего пинга
def calculate_ping(domain):
    try:
        proc = subprocess.run(
            ["ping", "-c", "5", domain],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            text=True,
        )
        if proc.returncode == 0:
            for line in proc.stdout.split("\n"):
                if "rtt min/avg/max/mdev" in line:
                    avg_ping = line.split("/")[4]
                    results["ping"] = float(avg_ping)
                    break
            if results["ping"] is not None:
                if results["ping"] < 50:
                    results["rating"] = 5
                elif results["ping"] < 100:
                    results["rating"] = 4
                elif results["ping"] < 200:
                    results["rating"] = 3
                elif results["ping"] < 300:
                    results["rating"] = 2
                else:
                    results["rating"] = 1
                results["positives"].append(f"Средний пинг: {results['ping']} мс (Рейтинг: {results['rating']}/5)")
            else:
                results["negatives"].append("Не удалось определить средний пинг")
        else:
            results["negatives"].append("Не удалось выполнить пинг до хоста")
    except Exception as e:
        results["negatives"].append(f"Ошибка при вычислении пинга: {e}")

# Функция для отображения результатов
def display_results():
    console.print("\n[bold cyan]===== Результаты проверки =====[/bold cyan]\n")
    if results["negatives"]:
        # Если единственный отрицательный момент - использование CDN
        if len(results["negatives"]) == 1 and "Использование CDN" in results["negatives"][0]:
            console.print("[bold yellow]Сайт не рекомендуется по следующим причинам:[/bold yellow]")
            for negative in results["negatives"]:
                console.print(f"[yellow]- {negative}[/yellow]")
        else:
            console.print("[bold red]Сайт НЕ ПОДХОДИТ по следующим причинам:[/bold red]")
            for negative in results["negatives"]:
                console.print(f"[yellow]- {negative}[/yellow]")
    else:
        console.print("[bold green]Сайт подходит по следующим причинам:[/bold green]")
        for positive in results["positives"]:
            console.print(f"[green]- {positive}[/green]")

    if results["positives"] and results["negatives"]:
        console.print("\n[bold green]Положительные моменты:[/bold green]")
        for positive in results["positives"]:
            console.print(f"[green]- {positive}[/green]")

# Основная функция
def main(domain):
    results["domain"] = domain

    # Создаем прогресс-бар
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        transient=True,
    ) as progress:
        tasks = []
        tasks.append(progress.add_task(description="Проверка поддержки TLS 1.3...", total=None))
        tasks.append(progress.add_task(description="Проверка поддержки HTTP/2...", total=None))
        tasks.append(progress.add_task(description="Проверка наличия CDN...", total=None))
        tasks.append(progress.add_task(description="Проверка переадресации...", total=None))
        tasks.append(progress.add_task(description="Вычисление пинга...", total=None))

        threads = []

        # Запускаем проверки в отдельных потоках
        t_tls = threading.Thread(target=lambda: [check_tls(domain), progress.update(tasks[0], completed=1)])
        t_http2 = threading.Thread(target=lambda: [check_http2(domain), progress.update(tasks[1], completed=1)])
        t_cdn = threading.Thread(target=lambda: [check_cdn(domain), progress.update(tasks[2], completed=1)])
        t_redirect = threading.Thread(target=lambda: [check_redirect(domain), progress.update(tasks[3], completed=1)])
        t_ping = threading.Thread(target=lambda: [calculate_ping(domain), progress.update(tasks[4], completed=1)])

        threads.extend([t_tls, t_http2, t_cdn, t_redirect, t_ping])

        for t in threads:
            t.start()
            time.sleep(0.1)  # Немного подождем для красоты анимации

        for t in threads:
            t.join()

    # Отображаем результаты
    display_results()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        console.print("[bold red]Использование: python script.py <домен>[/bold red]")
        sys.exit(1)
    domain = sys.argv[1]
    main(domain)

# Ваш Python-скрипт заканчивается здесь
EOF
