import sys
import subprocess
import requests
import time
import threading
import socket
import shutil
import json

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

console = Console()

# Global results
results = {
    "domain": "",
    "port": None,
    "tls_supported": False,
    "http2_supported": False,
    "cdn_used": False,
    "redirect_found": False,
    "ping": None,
    "rating": 0,
    "cdn_provider": None,
    "cdns": [],
    "negatives": [],
    "positives": [],
}

def check_and_install_command(command_name):
    if shutil.which(command_name) is None:
        console.print(f"[yellow]Утилита {command_name} не найдена. Устанавливаю...[/yellow]")
        proc = subprocess.run(
            ["sudo", "apt-get", "install", "-y", command_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if shutil.which(command_name) is None:
            console.print(f"[red]Ошибка: не удалось установить {command_name}. Установите её вручную.[/red]")
            sys.exit(1)

def check_port_availability(domain, port, timeout=5):
    try:
        with socket.create_connection((domain, port), timeout=timeout):
            return True
    except:
        return False

def check_tls(domain, port, progress, task_id):
    try:
        progress.update(task_id, description="Проверка поддержки TLS 1.3...")
        proc = subprocess.run(
            ["openssl", "s_client", "-connect", f"{domain}:{port}", "-tls1_3"],
            input="",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            text=True,
        )
        output = proc.stdout + proc.stderr
        if proc.returncode == 0 and ("TLSv1.3" in output or "New, TLSv1.3" in output):
            results["tls_supported"] = True
            results["positives"].append("Поддерживается TLS 1.3")
            progress.update(task_id, description="[green]TLS 1.3 поддерживается[/green]", completed=1)
        else:
            # Try to get the used TLS version
            proc = subprocess.run(
                ["openssl", "s_client", "-connect", f"{domain}:{port}"],
                input="",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
                text=True,
            )
            output = proc.stdout + proc.stderr
            tls_version = None
            for line in output.splitlines():
                if "Protocol  :" in line or "Protocol :" in line:
                    tls_version = line.split(":", 1)[1].strip()
                    break
            if tls_version:
                results["negatives"].append(f"Не поддерживается TLS 1.3 (используется {tls_version})")
                progress.update(task_id, description=f"[yellow]TLS 1.3 не поддерживается[/yellow] ({tls_version})", completed=1)
            else:
                results["negatives"].append("Не удалось определить используемую версию TLS")
                progress.update(task_id, description="[red]Не удалось определить версию TLS[/red]", completed=1)
    except subprocess.TimeoutExpired:
        results["negatives"].append("Не удалось подключиться для проверки TLS")
        progress.update(task_id, description="[red]Ошибка при проверке TLS[/red]", completed=1)
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке TLS: {e}")
        progress.update(task_id, description="[red]Ошибка при проверке TLS[/red]", completed=1)

def check_http2(domain, port, progress, task_id):
    try:
        progress.update(task_id, description="Проверка поддержки HTTP/2...")
        proc = subprocess.run(
            ["curl", "-I", "-s", "--http2", f"https://{domain}:{port}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            text=True,
        )
        if "HTTP/2" in proc.stdout or "HTTP/2" in proc.stderr:
            results["http2_supported"] = True
            results["positives"].append("Поддерживается HTTP/2")
            progress.update(task_id, description="[green]HTTP/2 поддерживается[/green]", completed=1)
        else:
            # If HTTP/2 is not supported, perform a regular request
            proc = subprocess.run(
                ["curl", "-I", "-s", f"https://{domain}:{port}"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                text=True,
            )
            http_version = None
            for line in proc.stdout.splitlines():
                if line.startswith("HTTP/"):
                    http_version = line.split(" ", 1)[0].strip()
                    break
            if http_version:
                results["negatives"].append(f"Не поддерживается HTTP/2 (используется {http_version})")
                progress.update(task_id, description=f"[yellow]HTTP/2 не поддерживается[/yellow] ({http_version})", completed=1)
            else:
                results["negatives"].append("Не удалось определить версию HTTP")
                progress.update(task_id, description="[red]Не удалось определить версию HTTP[/red]", completed=1)
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке HTTP/2: {e}")
        progress.update(task_id, description="[red]Ошибка при проверке HTTP/2[/red]", completed=1)

def check_cdn(domain, port, progress, task_id):
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
    cdn_detected = False
    try:
        progress.update(task_id, description="Проверка наличия CDN...")
        response = requests.head(f"https://{domain}:{port}", timeout=5)
        headers = response.headers
        header_str = str(headers).lower()
        for key, provider in cdn_providers.items():
            if key in header_str:
                results["cdn_used"] = True
                results["cdn_provider"] = provider
                results["cdns"].append(provider)
                cdn_detected = True
                break
        if not cdn_detected:
            results["positives"].append("CDN не используется")
            progress.update(task_id, description="[green]CDN не используется[/green]", completed=1)
        else:
            results["negatives"].append(f"Используется CDN: {provider}")
            progress.update(task_id, description=f"[yellow]Используется[/yellow] ({provider})", completed=1)
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке CDN: {e}")
        progress.update(task_id, description="[red]Ошибка при проверке CDN[/red]", completed=1)

def check_redirect(domain, port, progress, task_id):
    try:
        progress.update(task_id, description="Проверка переадресации...")
        response = requests.get(f"https://{domain}:{port}", timeout=5, allow_redirects=False)
        if 300 <= response.status_code < 400:
            results["redirect_found"] = True
            results["negatives"].append(f"Найдена переадресация: {response.headers.get('Location')}")
            progress.update(task_id, description="[yellow]Переадресация найдена[/yellow]", completed=1)
        else:
            results["positives"].append("Переадресация отсутствует")
            progress.update(task_id, description="[green]Переадресация отсутствует[/green]", completed=1)
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке переадресации: {e}")
        progress.update(task_id, description="[red]Ошибка при проверке переадресации[/red]", completed=1)

def calculate_ping(domain, progress, task_id):
    try:
        progress.update(task_id, description="Вычисление пинга...")
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
                # Assign rating based on new thresholds
                if results["ping"] <= 2:
                    results["rating"] = 5
                elif results["ping"] <= 3:
                    results["rating"] = 4
                elif results["ping"] <= 5:
                    results["rating"] = 3
                elif results["ping"] <= 8:
                    results["rating"] = 2
                else:
                    results["rating"] = 1
                # Now decide whether to add to positives or negatives
                if results["rating"] >= 4:
                    results["positives"].append(f"Средний пинг: {results['ping']} мс (Рейтинг: {results['rating']}/5)")
                else:
                    results["negatives"].append(f"Высокий пинг: {results['ping']} мс (Рейтинг: {results['rating']}/5)")
                progress.update(task_id, description=f"Вычисление пинга... [green]{results['ping']} мс[/green]", completed=1)
            else:
                results["negatives"].append("Не удалось определить средний пинг")
                progress.update(task_id, description="[red]Не удалось определить средний пинг[/red]", completed=1)
        else:
            results["negatives"].append("Не удалось выполнить пинг до хоста")
            progress.update(task_id, description="[red]Не удалось выполнить пинг[/red]", completed=1)
    except Exception as e:
        results["negatives"].append(f"Ошибка при вычислении пинга: {e}")
        progress.update(task_id, description="[red]Ошибка при вычислении пинга[/red]", completed=1)

def display_results():
    console.print("\n[bold cyan]===== Результаты проверки =====[/bold cyan]\n")
    reasons = []
    positives = []

    if results["tls_supported"]:
        positives.append("Поддерживается TLS 1.3")
    else:
        reasons.append("Не поддерживается TLS 1.3")

    if results["http2_supported"]:
        positives.append("Поддерживается HTTP/2")
    else:
        reasons.append("Не поддерживается HTTP/2")

    if results["cdn_used"]:
        cdn_list = ', '.join(results["cdns"])
        reasons.append(f"Используется CDN: {cdn_list}")
    else:
        positives.append("CDN не используется")

    if not results["redirect_found"]:
        positives.append("Переадресация отсутствует")
    else:
        reasons.append("Найдена переадресация")

    # Include ping rating
    if results["ping"] is not None:
        if results["rating"] >= 4:
            positives.append(f"Средний пинг: {results['ping']} мс (Рейтинг: {results['rating']}/5)")
        else:
            reasons.append(f"Высокий пинг: {results['ping']} мс (Рейтинг: {results['rating']}/5)")
    else:
        reasons.append("Не удалось определить средний пинг")

    # Determine if the host is acceptable
    acceptable = False
    if results.get("rating", 0) >= 4:
        if not reasons:
            acceptable = True
        elif len(reasons) == 1 and "Используется CDN" in reasons[0]:
            acceptable = True
        else:
            acceptable = False
    else:
        acceptable = False

    # Output the results
    if acceptable:
        console.print("[bold green]Сайт подходит как SNI для Reality по следующим причинам:[/bold green]")
        for positive in positives:
            console.print(f"[green]- {positive}[/green]")
    else:
        console.print("[bold red]Сайт НЕ ПОДХОДИТ по следующим причинам:[/bold red]")
        for reason in reasons:
            console.print(f"[yellow]- {reason}[/yellow]")
        if positives:
            console.print("\n[bold green]Положительные моменты:[/bold green]")
            for positive in positives:
                console.print(f"[green]- {positive}[/green]")

    # Final message
    port_display = results['port'] if results['port'] else '443/80'
    if acceptable:
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

    # Check necessary commands
    check_and_install_command("openssl")
    check_and_install_command("curl")
    check_and_install_command("dig")
    check_and_install_command("whois")

    console.print(f"\n[bold cyan]Проверка хоста:[/bold cyan] {domain}")
    if port:
        console.print(f"[bold cyan]Порт:[/bold cyan] {port}")
        ports_to_check = [port]
    else:
        console.print(f"[bold cyan]Порты по умолчанию:[/bold cyan] 443, 80")
        ports_to_check = [443, 80]

    # Check port availability
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

    # Create progress bar
    with Progress(
        SpinnerColumn(finished_text=""),
        TextColumn("{task.description}"),
    ) as progress:
        tasks = {}
        tasks['tls'] = progress.add_task("Проверка поддержки TLS 1.3...", total=1)
        tasks['http2'] = progress.add_task("Проверка поддержки HTTP/2...", total=1)
        tasks['cdn'] = progress.add_task("Проверка наличия CDN...", total=1)
        tasks['redirect'] = progress.add_task("Проверка переадресации...", total=1)
        tasks['ping'] = progress.add_task("Вычисление пинга...", total=1)

        threads = []

        # Start checks in separate threads
        t_tls = threading.Thread(target=check_tls, args=(domain, port, progress, tasks['tls']))
        t_http2 = threading.Thread(target=check_http2, args=(domain, port, progress, tasks['http2']))
        t_cdn = threading.Thread(target=check_cdn, args=(domain, port, progress, tasks['cdn']))
        t_redirect = threading.Thread(target=check_redirect, args=(domain, port, progress, tasks['redirect']))
        t_ping = threading.Thread(target=calculate_ping, args=(domain, progress, tasks['ping']))

        threads.extend([t_tls, t_http2, t_cdn, t_redirect, t_ping])

        for t in threads:
            t.start()
            time.sleep(0.1)

        for t in threads:
            t.join()

    # Display results
    display_results()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        console.print("[bold red]Использование: script.py <домен[:порт]>[/bold red]")
        sys.exit(1)
    domain_input = sys.argv[1]
    main(domain_input)
