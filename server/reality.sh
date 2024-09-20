#!/bin/bash

# Function to check Python and run appropriate script
check_python_and_run() {
    local py_script=$1
    local bash_script=$2
    local domain_port=$3

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
            echo "All libraries are available. Running python script..."
            python3 <(wget -qO- "$py_script") "$domain_port" &
        else
            echo "Missing libraries. Running bash script..."
            bash <(wget -qO- "$bash_script") "$domain_port" &
        fi
    else
        echo "Python3 is not installed. Running bash script..."
        bash <(wget -qO- "$bash_script") "$domain_port" &
    fi
}

# Check if a domain argument is provided
if [ -z "$1" ]; then
    echo "Please provide a domain as an argument."
    echo "Usage: $0 <domain> [port]"
    exit 1
fi

domain_port=$1

# Check if a port argument is provided
if [ ! -z "$2" ]; then
    domain_port="$1:$2"
fi

# ANSI color codes for highlighting
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No color

# Menu for user selection
echo -e "The domain being checked is: ${GREEN}$domain_port${NC}"
echo -e "Select an option to check:"
echo -e "1. Check host '$domain_port' for use as ${GREEN}Reality ServerName${NC}"
echo -e "2. Check host '$domain_port' for use as ${RED}Reality Dest${NC}"

read -p "Enter your choice (1 or 2): " choice

case $choice in
    1)
        echo -e "You selected: Checking host '$domain_port' for ${GREEN}Reality ServerName${NC}"
        check_python_and_run "https://dignezzz.github.io/server/sni.py" "https://dignezzz.github.io/server/sni.sh" "$domain_port"
        ;;
    2)
        echo -e "You selected: Checking host '$domain_port' for ${RED}Reality Dest${NC}"
        check_python_and_run "https://dignezzz.github.io/server/dest.py" "https://dignezzz.github.io/server/dest.sh" "$domain_port"
        ;;
    *)
        echo "Invalid choice. Please enter 1 or 2."
        ;;
esac
