#!/bin/bash

# Check if the script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "\e[31mPlease run the script as root (sudo).\e[0m"
        exit 1
    fi
}

# Detect OS and version
detect_os() {
    os_name=$(lsb_release -is 2>/dev/null || grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    os_version=$(lsb_release -rs 2>/dev/null || grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    echo -e "\e[34mDetected system: $os_name $os_version\e[0m"
}

# Get the current SSH port from a config file
get_current_port() {
    local config_file=$1
    if [ -f "$config_file" ]; then
        grep -Po '(?<=^Port )\d+' "$config_file" || echo "22"
    else
        echo "22"
    fi
}

# Change the port in the config file
change_port_in_config() {
    local config_file=$1
    local port=$2
    if [ -f "$config_file" ]; then
        sed -i "s/^#Port 22/Port $port/" "$config_file"
        sed -i "s/^Port [0-9]\+/Port $port/" "$config_file"
        echo -e "\e[32mPort was changed in the file: $config_file\e[0m"
        echo -e "\e[32mNew port: $port\e[0m"
    fi
}

# Reload the SSH service
reload_ssh_service() {
    if command -v systemctl > /dev/null; then
        systemctl daemon-reload
        systemctl restart ssh || systemctl restart sshd
    else
        service ssh restart || service sshd restart
    fi
}

# Check if the port is available
check_port_availability() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        echo -e "\e[31mError: Port $port is already in use by another process.\e[0m"
        exit 1
    fi
}

# Prompt for a new port from the user
prompt_for_port() {
    read -p "Enter a new port for SSH (1-65535): " new_port

    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo -e "\e[31mError: Port must be a number between 1 and 65535.\e[0m"
        exit 1
    fi

    check_port_availability "$new_port"
    echo "$new_port"
}

# Change the SSH port for Ubuntu 24.04
change_port_ubuntu_2404() {
    local current_port=$(get_current_port "/lib/systemd/system/ssh.socket")
    echo -e "\e[33mCurrent SSH port: $current_port\e[0m"
    
    local new_port=$(prompt_for_port)
    
    sed -i "s/^ListenStream=.*/ListenStream=$new_port/" "/lib/systemd/system/ssh.socket"
    change_port_in_config "/etc/ssh/sshd_config" "$new_port"
    reload_ssh_service
    
    echo -e "\e[32mSSH port successfully changed to $new_port.\e[0m"
    check_firewall_rules "$new_port"
}

# Change the SSH port for other systems
change_port_other_systems() {
    local current_port=$(get_current_port "/etc/ssh/sshd_config")
    echo -e "\e[33mCurrent SSH port: $current_port\e[0m"
    
    local new_port=$(prompt_for_port)
    
    change_port_in_config "/etc/ssh/sshd_config" "$new_port"
    reload_ssh_service
    
    echo -e "\e[32mSSH port successfully changed to $new_port.\e[0m"
    check_firewall_rules "$new_port"
}

# Check and open the new port in ufw or iptables
check_firewall_rules() {
    local port=$1
    if command -v ufw > /dev/null; then
        if ufw status | grep -q "inactive"; then
            echo -e "\e[33mUFW is inactive, skipping UFW rules.\e[0m"
        else
            ufw allow "$port"/tcp
            ufw reload
            echo -e "\e[32mPort $port has been allowed in UFW.\e[0m"
        fi
    elif command -v iptables > /dev/null; then
        if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
            echo -e "\e[32mPort $port has been allowed in iptables.\e[0m"
        else
            echo -e "\e[33mPort $port is already allowed in iptables.\e[0m"
        fi
    else
        echo -e "\e[31mNo firewall (ufw or iptables) detected. Please ensure port $port is open manually.\e[0m"
    fi
}

# Main function
main() {
    check_root
    detect_os

    case "$os_name" in
        Ubuntu)
            if [[ "$os_version" == "24.04" ]]; then
                change_port_ubuntu_2404
            else
                change_port_other_systems
            fi
            ;;
        CentOS|Fedora|RHEL|Debian)
            change_port_other_systems
            ;;
        *)
            echo -e "\e[31mOperating system not supported by this script.\e[0m"
            exit 1
            ;;
    esac

    # Display connection info
    echo -e "\e[34m----------------------------------------------------\e[0m"
    echo -e "\e[32mCreated by DigneZzZ\e[0m"
    echo -e "\e[36mJoin my community: https://openode.xyz\e[0m"
}

# Run the main function
main
