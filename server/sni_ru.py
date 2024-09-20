import sys
import subprocess
import threading
import time
import socket
import json
import shutil

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.table import Table

console = Console()

# Global results
results = {
    "domain": "",
    "tls_supported": False,
    "http2_supported": False,
    "http3_supported": False,
    "cdn_used": False,
    "redirect_found": False,
    "negatives": [],
    "positives": [],
    "cdns": [],
}

# Check and install command if not available
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

# Check TLS 1.3 support
def check_tls(domain, progress, task_id):
    try:
        progress.update(task_id, description="Проверка поддержки TLS 1.3...")
        proc = subprocess.run(
            ["openssl", "s_client", "-connect", f"{domain}:443", "-tls1_3"],
            input="",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            text=True,
        )
        output = proc.stdout + proc.stderr
        if "TLSv1.3" in output:
            results["tls_supported"] = True
            results["positives"].append("Поддерживается TLS 1.3")
            progress.update(task_id, description="[green]TLS 1.3 поддерживается[/green]", completed=1)
        else:
            # Try to get the used TLS version
            proc = subprocess.run(
                ["openssl", "s_client", "-connect", f"{domain}:443"],
                input="",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                text=True,
            )
            output = proc.stdout + proc.stderr
            for line in output.splitlines():
                if "Protocol  :" in line or "Protocol :" in line:
                    tls_version = line.split(":", 1)[1].strip()
                    results["negatives"].append(f"TLS 1.3 не поддерживается. Используемая версия: {tls_version}")
                    progress.update(task_id, description=f"[yellow]TLS 1.3 не поддерживается[/yellow] ({tls_version})", completed=1)
                    break
            else:
                results["negatives"].append("Не удалось определить используемую версию TLS")
                progress.update(task_id, description="[red]Не удалось определить версию TLS[/red]", completed=1)
    except subprocess.TimeoutExpired:
        results["negatives"].append("Не удалось подключиться для проверки TLS")
        progress.update(task_id, description="[red]Ошибка при проверке TLS[/red]", completed=1)
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке TLS: {e}")
        progress.update(task_id, description="[red]Ошибка при проверке TLS[/red]", completed=1)

# Check HTTP versions support
def check_http_versions(domain, progress, task_ids):
    http2_task_id, http3_task_id = task_ids

    # Check HTTP/2
    try:
        progress.update(http2_task_id, description="Проверка поддержки HTTP/2...")
        proc = subprocess.run(
            ["curl", "-I", "-s", "--max-time", "5", "--http2", f"https://{domain}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if "HTTP/2" in proc.stdout:
            results["http2_supported"] = True
            results["positives"].append("Поддерживается HTTP/2")
            progress.update(http2_task_id, description="[green]HTTP/2 поддерживается[/green]", completed=1)
        else:
            # Additional checks with openssl
            proc = subprocess.run(
                ["openssl", "s_client", "-alpn", "h2", "-connect", f"{domain}:443"],
                input="",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                text=True,
            )
            if "ALPN protocol: h2" in proc.stdout:
                results["http2_supported"] = True
                results["positives"].append("Поддерживается HTTP/2")
                progress.update(http2_task_id, description="[green]HTTP/2 поддерживается[/green]", completed=1)
            else:
                results["negatives"].append("HTTP/2 не поддерживается")
                progress.update(http2_task_id, description="[yellow]HTTP/2 не поддерживается[/yellow]", completed=1)
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке HTTP/2: {e}")
        progress.update(http2_task_id, description="[red]Ошибка при проверке HTTP/2[/red]", completed=1)

    # Check HTTP/3
    try:
        progress.update(http3_task_id, description="Проверка поддержки HTTP/3...")
        proc = subprocess.run(
            ["openssl", "s_client", "-alpn", "h3", "-connect", f"{domain}:443"],
            input="",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            text=True,
        )
        if "ALPN protocol: h3" in proc.stdout or "ALPN protocol: h3" in proc.stderr:
            results["http3_supported"] = True
            results["positives"].append("Поддерживается HTTP/3")
            progress.update(http3_task_id, description="[green]HTTP/3 поддерживается[/green]", completed=1)
        else:
            results["negatives"].append("HTTP/3 не поддерживается или не удалось определить")
            progress.update(http3_task_id, description="[yellow]HTTP/3 не поддерживается[/yellow]", completed=1)
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке HTTP/3: {e}")
        progress.update(http3_task_id, description="[red]Ошибка при проверке HTTP/3[/red]", completed=1)

# Check for redirects
def check_redirect(domain, progress, task_id):
    try:
        progress.update(task_id, description="Проверка наличия переадресаций...")
        proc = subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", "%{redirect_url}", "--max-time", "5", f"https://{domain}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        redirect_url = proc.stdout.strip()
        if redirect_url:
            results["redirect_found"] = True
            results["negatives"].append(f"Найдена переадресация: {redirect_url}")
            progress.update(task_id, description=f"[yellow]Переадресация найдена[/yellow]: {redirect_url}", completed=1)
        else:
            results["positives"].append("Переадресация отсутствует")
            progress.update(task_id, description="[green]Переадресация отсутствует[/green]", completed=1)
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке переадресации: {e}")
        progress.update(task_id, description="[red]Ошибка при проверке переадресации[/red]", completed=1)

# Check for CDN usage
def check_cdn(domain, progress, task_id):
    cdn_detected = False

    # CDN providers to check
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
        progress.update(task_id, description="Анализ HTTP-заголовков для определения CDN...")
        proc = subprocess.run(
            ["curl", "-s", "-I", "--max-time", "5", f"https://{domain}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        headers = proc.stdout.lower()
        for key, provider in cdn_providers.items():
            if key in headers:
                results["cdn_used"] = True
                results["cdns"].append(f"{provider} (по заголовкам)")
                cdn_detected = True
                break

        if not cdn_detected:
            # Check ASN
            progress.update(task_id, description="Проверка ASN для определения CDN...")
            proc = subprocess.run(
                ["dig", "+short", domain],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            ip = proc.stdout.strip().split('\n')[0]
            if ip:
                proc = subprocess.run(
                    ["whois", "-h", "whois.cymru.com", f" -v {ip}"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                asn_info = proc.stdout.strip().split('\n')[-1]
                owner = ' '.join(asn_info.split()[4:])
                for key, provider in cdn_providers.items():
                    if key in owner.lower():
                        results["cdn_used"] = True
                        results["cdns"].append(f"{provider} (по ASN)")
                        cdn_detected = True
                        break

        if not cdn_detected:
            # Check ipinfo.io
            progress.update(task_id, description="Использование ipinfo.io для определения CDN...")
            if shutil.which("jq") is None:
                check_and_install_command("jq")
            proc = subprocess.run(
                ["dig", "+short", domain],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            ip = proc.stdout.strip().split('\n')[0]
            if ip:
                proc = subprocess.run(
                    ["curl", "-s", f"https://ipinfo.io/{ip}/json"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                json_output = proc.stdout
                data = json.loads(json_output)
                org = data.get("org", "")
                for key, provider in cdn_providers.items():
                    if key in org.lower():
                        results["cdn_used"] = True
                        results["cdns"].append(f"{provider} (через ipinfo.io)")
                        cdn_detected = True
                        break

        if not cdn_detected:
            # Check SSL certificate
            progress.update(task_id, description="Анализ SSL-сертификата для определения CDN...")
            proc = subprocess.run(
                ["openssl", "s_client", "-connect", f"{domain}:443"],
                input="",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                text=True,
            )
            cert_info = proc.stdout + proc.stderr
            for key, provider in cdn_providers.items():
                if key in cert_info.lower():
                    results["cdn_used"] = True
                    results["cdns"].append(f"{provider} (по SSL-сертификату)")
                    cdn_detected = True
                    break

        if results["cdn_used"]:
            cdn_list = ', '.join(results["cdns"])
            results["negatives"].append(f"Используется CDN: {cdn_list}")
            progress.update(task_id, description=f"[yellow]Используется CDN[/yellow]: {cdn_list}", completed=1)
        else:
            results["positives"].append("CDN не используется")
            progress.update(task_id, description="[green]CDN не используется[/green]", completed=1)
    except Exception as e:
        results["negatives"].append(f"Ошибка при проверке CDN: {e}")
        progress.update(task_id, description="[red]Ошибка при проверке CDN[/red]", completed=1)

# Display the final results
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

    if not reasons:
        console.print("[bold green]Сайт подходит как SNI для Reality по следующим причинам:[/bold green]")
        for positive in positives:
            console.print(f"[green]- {positive}[/green]")
    else:
        console.print("[bold red]Сайт не подходит как SNI для Reality по следующим причинам:[/bold red]")
        for reason in reasons:
            console.print(f"[yellow]- {reason}[/yellow]")
        if positives:
            console.print("\n[bold green]Положительные моменты:[/bold green]")
            for positive in positives:
                console.print(f"[green]- {positive}[/green]")

# Main function
def main():
    if len(sys.argv) != 2:
        console.print("[bold red]Использование: script.py <домен>[/bold red]")
        sys.exit(1)

    domain = sys.argv[1]
    results["domain"] = domain

    # Check necessary commands
    check_and_install_command("openssl")
    check_and_install_command("curl")
    check_and_install_command("dig")
    check_and_install_command("whois")

    console.print(f"\n[bold cyan]Выполняется проверка для домена:[/bold cyan] {domain}")

    # Create progress bar
    with Progress(
        SpinnerColumn(finished_text=""),
        TextColumn("{task.description}"),
    ) as progress:
        tasks = {}
        tasks['tls'] = progress.add_task("Проверка поддержки TLS 1.3...", total=1)
        tasks['http2'] = progress.add_task("Проверка поддержки HTTP/2...", total=1)
        tasks['http3'] = progress.add_task("Проверка поддержки HTTP/3...", total=1)
        tasks['redirect'] = progress.add_task("Проверка наличия переадресаций...", total=1)
        tasks['cdn'] = progress.add_task("Проверка использования CDN...", total=1)

        threads = []

        t_tls = threading.Thread(target=check_tls, args=(domain, progress, tasks['tls']))
        t_http_versions = threading.Thread(target=check_http_versions, args=(domain, progress, (tasks['http2'], tasks['http3'])))
        t_redirect = threading.Thread(target=check_redirect, args=(domain, progress, tasks['redirect']))
        t_cdn = threading.Thread(target=check_cdn, args=(domain, progress, tasks['cdn']))

        threads.extend([t_tls, t_http_versions, t_redirect, t_cdn])

        for t in threads:
            t.start()
            time.sleep(0.1)

        for t in threads:
            t.join()

    # Display the results
    display_results()

if __name__ == "__main__":
    main()
