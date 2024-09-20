import sys
import subprocess
import requests
import time
import threading
import socket

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

console = Console()

# Глобальные результаты
results = {
    "domain": "",
    "port": None,
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

def check_port_availability(domain, port, timeout=5):
    try:
        with socket.create_connection((domain, port), timeout=timeout):
            return True
    except:
        return False

def check_tls(domain, port):
    try:
        # Попытка подключения с использованием TLS 1.3
        proc = subprocess.run(
            ["openssl", "s_client", "-connect", f"{domain}:{port}", "-tls1_3"],
            input="",  # Передаем пустую строку, чтобы избежать зависания
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=10,
            text=True,
        )
        output = proc.stdout

        if "Protocol  : TLSv1.3" in output:
            results["tls"] = True
            results["positives"].append("Поддерживается TLS 1.3")
        else:
            # Если TLS 1.3 не поддерживается, пробуем без указания версии
            proc = subprocess.run(
                ["openssl", "s_client", "-connect", f"{domain}:{port}"],
                input="",
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=10,
                text=True,
            )
            output = proc.stdout
            # Ищем строку с версией протокола
            for line in output.splitlines():
                if "Protocol  :" in line:
                    tls_version = line.split(":", 1)[1].strip()
                    results["negatives"].append(f"Не поддерживается TLS 1.3 (используется {tls_version})")
                    break
            else:
                results["negatives"].append("Не поддерживается TLS 1.3 (не удалось определить текущую версию TLS)")
    except subprocess.TimeoutExpired:
        results["negatives"].append("Время ожидания подключения истекло при проверке TLS")
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке TLS: {e}")

def check_http2(domain, port):
    try:
        # Пробуем запрос с поддержкой HTTP/2
        proc = subprocess.run(
            ["curl", "-I", "-s", "--http2", f"https://{domain}:{port}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            text=True,
        )
        if "HTTP/2" in proc.stdout:
            results["http2"] = True
            results["positives"].append("Поддерживается HTTP/2")
        else:
            # Если HTTP/2 не поддерживается, выполняем обычный запрос
            proc = subprocess.run(
                ["curl", "-I", "-s", f"https://{domain}:{port}"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                text=True,
            )
            # Ищем строку со статусом ответа
            for line in proc.stdout.splitlines():
                if line.startswith("HTTP/"):
                    http_version = line.split(" ", 1)[0].strip()
                    results["negatives"].append(f"Не поддерживается HTTP/2 (используется {http_version})")
                    break
            else:
                results["negatives"].append("Не удалось определить версию HTTP")
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке HTTP/2: {e}")

def check_cdn(domain, port):
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
        response = requests.head(f"https://{domain}:{port}", timeout=5)
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

def check_redirect(domain, port):
    try:
        response = requests.get(f"https://{domain}:{port}", timeout=5, allow_redirects=False)
        if 300 <= response.status_code < 400:
            results["redirect"] = True
            results["negatives"].append(f"Найдена переадресация: {response.headers.get('Location')}")
        else:
            results["positives"].append("Переадресация отсутствует")
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке переадресации: {e}")

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

def display_results():
    console.print("\n[bold cyan]===== Результаты проверки =====[/bold cyan]\n")
    if results["negatives"]:
        # Если единственный отрицательный момент - использование CDN
        if len(results["negatives"]) == 1 and any("Использование CDN" in neg for neg in results["negatives"]):
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

    # Итоговое сообщение
    port_display = results['port'] if results['port'] else '443/80'
    if not results["negatives"] or (len(results["negatives"]) == 1 and any("Использование CDN" in neg for neg in results["negatives"])):
        console.print(f"\n[bold green]Хост {results['domain']}:{port_display} подходит в качестве dest[/bold green]")
    else:
        console.print(f"\n[bold red]Хост {results['domain']}:{port_display} НЕ подходит в качестве dest[/bold red]")

def main(domain_input):
    if ':' in domain_input:
        domain, port = domain_input.split(':', 1)
        port = int(port)
    else:
        domain = domain_input
        port = None

    results["domain"] = domain
    results["port"] = port

    console.print(f"\n[bold cyan]Проверка хоста:[/bold cyan] {domain}")
    if port:
        console.print(f"[bold cyan]Порт:[/bold cyan] {port}")
        ports_to_check = [port]
    else:
        console.print(f"[bold cyan]Порты по умолчанию:[/bold cyan] 443, 80")
        ports_to_check = [443, 80]

    # Проверяем доступность портов
    for port in ports_to_check:
        if check_port_availability(domain, port):
            results["port"] = port
            console.print(f"[green]Порт {port} доступен. Продолжаем проверку...[/green]")
            break
        else:
            console.print(f"[yellow]Порт {port} недоступен. Пробуем следующий порт...[/yellow]")
    else:
        console.print(f"[red]Хост {domain} недоступен на портах {', '.join(map(str, ports_to_check))}[/red]")
        sys.exit(1)

    # Создаем прогресс-бар
    with Progress(
        SpinnerColumn(finished_text="✅"),
        TextColumn("{task.description}"),
    ) as progress:
        tasks = []
        tasks.append(progress.add_task("Проверка поддержки TLS 1.3...", total=1))
        tasks.append(progress.add_task("Проверка поддержки HTTP/2...", total=1))
        tasks.append(progress.add_task("Проверка наличия CDN...", total=1))
        tasks.append(progress.add_task("Проверка переадресации...", total=1))
        tasks.append(progress.add_task("Вычисление пинга...", total=1))

        threads = []

        # Запускаем проверки в отдельных потоках
        t_tls = threading.Thread(target=lambda: [check_tls(domain, port), progress.update(tasks[0], completed=1)])
        t_http2 = threading.Thread(target=lambda: [check_http2(domain, port), progress.update(tasks[1], completed=1)])
        t_cdn = threading.Thread(target=lambda: [check_cdn(domain, port), progress.update(tasks[2], completed=1)])
        t_redirect = threading.Thread(target=lambda: [check_redirect(domain, port), progress.update(tasks[3], completed=1)])
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
        console.print("[bold red]Использование: script.py <домен[:порт]>[/bold red]")
        sys.exit(1)
    domain_input = sys.argv[1]
    main(domain_input)
