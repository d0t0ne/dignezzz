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
            echo "All libraries are available. Running python script..."
            python3 <(wget -qO- "$py_script") "$domain" &
        else
            echo "Missing libraries. Running bash script..."
            bash <(wget -qO- "$bash_script") "$domain" &
        fi
    else
        echo "Python3 is not installed. Running bash script..."
        bash <(wget -qO- "$bash_script") "$domain" &
    fi
}

# Check if a domain argument is provided
if [ -z "$1" ]; then
    echo "Please provide a domain as an argument."
    echo "Usage: $0 <domain>"
    exit 1
fi

domain=$1

# ANSI color codes for highlighting
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No color

# Menu for user selection
echo -e "The domain being checked is: ${GREEN}$domain${NC}"
echo "Select an option to check:"
echo "1. Check host for use as ${GREEN}Reality ServerName${NC}"
echo "2. Check host for use as ${RED}Reality Dest${NC}"

read -p "Enter your choice (1 or 2): " choice

case $choice in
    1)
        echo -e "You selected: Checking for ${GREEN}Reality ServerName${NC}"
        check_python_and_run "https://dignezzz.github.io/server/sni.py" "https://dignezzz.github.io/server/sni.sh" "$domain"
        ;;
    2)
        echo -e "You selected: Checking for ${RED}Reality Dest${NC}"
        check_python_and_run "https://dignezzz.github.io/server/dest.py" "https://dignezzz.github.io/server/dest.sh" "$domain"
        ;;
    *)
        echo "Invalid choice. Please enter 1 or 2."
        ;;
esac

disown
