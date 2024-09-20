#!/bin/bash

check_python_and_run() {
    local py_script=$1
    local bash_script=$2

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
            python3 <(wget -qO- "$py_script") &
        else
            echo "Missing libraries. Running bash script..."
            bash <(wget -qO- "$bash_script") &
        fi
    else
        echo "Python3 is not installed. Running bash script..."
        bash <(wget -qO- "$bash_script") &
    fi
}

echo "Select an option to check:"
echo "1. Check host for use as Reality ServerName"
echo "2. Check host for use as Reality Dest"

read -p "Enter your choice (1 or 2): " choice

case $choice in
    1)
        check_python_and_run "https://dignezzz.github.io/server/sni.py" "https://dignezzz.github.io/server/sni.sh"
        ;;
    2)
        check_python_and_run "https://dignezzz.github.io/server/dest.py" "https://dignezzz.github.io/server/dest.sh"
        ;;
    *)
        echo "Invalid choice. Please enter 1 or 2."
        ;;
esac

disown
