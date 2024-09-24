#!/bin/bash

# Function to check Python and run appropriate script
check_python_and_run() {
    local py_script=$1
    local bash_script=$2
    local domain=$3

    if command -v python3 &>/dev/null; then
        echo "Python3 is installed. Checking required libraries..."

        python3 - <<EOF
import sys
try:
    import subprocess
    import requests
    import time
    import threading
    import socket
    import shutil
    import json
    from rich.console import Console
    from rich.progress import Progress, SpinnerColumn, TextColumn
except ImportError as e:
    print(f"Missing library: {e.name}")
    sys.exit(1)
EOF

        if [ $? -eq 0 ]; then
            python3 <(wget -qO- "$py_script") "$domain"
        else
            bash <(wget -qO- "$bash_script") "$domain"
        fi
    else
        bash <(wget -qO- "$bash_script") "$domain"
    fi
}

# ANSI color codes for highlighting
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No color

# Prompt user to enter the domain
read -p "Please enter the domain to check: " input_domain

# Validate the entered domain
if [ -z "$input_domain" ]; then
    echo -e "${RED}Error: No domain entered.${NC}"
    echo "Usage: Run the script and enter the domain when prompted."
    exit 1
fi

domain="$input_domain"
domain_port="$input_domain"

# Optionally, prompt for port
read -p "Do you want to specify a port? (y/n): " specify_port

if [[ "$specify_port" =~ ^[Yy]$ ]]; then
    read -p "Enter the port number: " port
    # Validate the port number
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}Invalid port number. Using default domain without port.${NC}"
    else
        domain_port="${domain}:${port}"
    fi
fi

# Menu for user selection
echo -e "\nThe domain being checked is: ${GREEN}$domain_port${NC}"
echo -e "Select an option to check:"
echo -e "1. Check host ${RED}'$domain'${NC} for use as ${GREEN}Reality ServerName${NC} (domain only)"
echo -e "2. Check host ${RED}'$domain_port'${NC} for use as ${GREEN}Reality Dest${NC}"

# Prompt for user choice
read -p "Enter your choice (1 or 2): " choice

# Handle user choice
case $choice in
    1)
        echo -e "\nYou selected: Checking host ${RED}'$domain'${NC} for Reality ServerName${NC}"
        check_python_and_run "https://dignezzz.github.io/server/sni.py" "https://dignezzz.github.io/server/sni.sh" "$domain"
        ;;
    2)
        echo -e "\nYou selected: Checking host ${RED}'$domain_port'${NC} for ${GREEN}Reality Dest${NC}"
        check_python_and_run "https://dignezzz.github.io/server/dest.py" "https://dignezzz.github.io/server/dest.sh" "$domain_port"
        ;;
    *)
        echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        exit 1
        ;;
esac
