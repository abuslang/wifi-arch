#!/bin/bash

# Script to list available WiFi networks and connect to them
# Version 1.3
# Usage: 
#   ./wifi.sh                           - List networks and connect to one
#   ./wifi.sh -l                        - Only list available networks
#   ./wifi.sh -n WifiName               - Connect to specified network (will prompt for password if needed)
#   ./wifi.sh -n WifiName -p password   - Connect to specified network with given password

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if required command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed.${NC}"
        echo "Please install NetworkManager and try again."
        exit 1
    fi
}

# Check if nmcli is installed
check_command "nmcli"

# Function to display usage
show_help() {
    echo "Usage: $0 [OPTION]..."
    echo "List available WiFi networks and connect to them."
    echo
    echo "Options:"
    echo "  -l, --list                 List available networks only, without connecting"
    echo "  -n, --name SSID            Connect to the network with the specified SSID"
    echo "  -p, --password PASSWORD    Use the specified password when connecting"
    echo "  -h, --help                 Display this help and exit"
    echo
    echo "Examples:"
    echo "  $0                         List networks and prompt to connect"
    echo "  $0 -l                      Only list available networks"
    echo "  $0 -n MyWifi              Connect to 'MyWifi', prompt for password"
    echo "  $0 -n MyWifi -p mypass    Connect to 'MyWifi' with password 'mypass'"
    echo
}

# Function to scan and list WiFi networks
scan_networks() {
    echo -e "${YELLOW}Scanning for WiFi networks...${NC}"
    echo
    
    # Get Wi-Fi networks, sort by signal strength, remove duplicates, and filter the top 5
    networks=$(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list | sort -t: -k2 -nr | awk -F: '!seen[$1]++' | head -n 5)
    
    if [ -z "$networks" ]; then
        echo -e "${RED}No WiFi networks found.${NC}"
        exit 1
    fi
    
    # Display networks with numbers
    echo -e "${YELLOW}Available Networks:${NC}"
    echo "-----------------"
    counter=1
    while IFS= read -r line; do
        ssid=$(echo "$line" | cut -d ':' -f 1)
        signal=$(echo "$line" | cut -d ':' -f 2)
        security=$(echo "$line" | cut -d ':' -f 3)
        
        # Skip networks with empty SSID (hidden networks)
        if [ -z "$ssid" ]; then
            continue
        fi
        
        # If security is empty, mark as "Open"
        if [ -z "$security" ]; then
            security="Open"
        fi
        
        # Store the SSID for later use
        network_list[$counter]=$ssid
        
        # Print network information
        echo -e "$counter. ${GREEN}$ssid${NC} (Signal: $signal%, Security: $security)"
        
        counter=$((counter+1))
    done <<< "$networks"
    
    echo
}

# Function to check if a network exists
check_network_exists() {
    local target_ssid="$1"
    local all_networks
    
    all_networks=$(nmcli -t -f SSID device wifi list)
    if echo "$all_networks" | grep -q "^$target_ssid$"; then
        return 0  # Network exists
    else
        return 1  # Network doesn't exist
    fi
}

# Function to connect to a selected network
connect_to_network() {
    local choice=$1
    local ssid=${network_list[$choice]}
    
    if [ -z "$ssid" ]; then
        echo -e "${RED}Invalid selection.${NC}"
        exit 1
    fi
    
    # Check if we're already connected to this network
    current_connection=$(nmcli -t -f NAME connection show --active | grep "^$ssid$")
    if [ -n "$current_connection" ]; then
        echo -e "${GREEN}Already connected to $ssid${NC}"
        exit 0
    fi
    
    # Check if the network is already configured in NetworkManager
    saved_connection=$(nmcli -t -f NAME connection show | grep "^$ssid$")
    
    if [ -n "$saved_connection" ]; then
        # Connect using the saved connection
        echo -e "${YELLOW}Connecting to saved network: $ssid${NC}"
        if nmcli connection up "$ssid"; then
            echo -e "${GREEN}Successfully connected to $ssid${NC}"
        else
            echo -e "${RED}Failed to connect to $ssid. The saved connection might have issues.${NC}"
        fi
        return
    fi
    
    # Handle new connections
    # Check if the network has security
    security=$(nmcli -t -f SSID,SECURITY device wifi list | grep "^$ssid:" | cut -d ':' -f 2)
    
    if [ -z "$security" ] || [ "$security" = "--" ]; then
        # Connect to open network
        echo -e "${YELLOW}Connecting to open network: $ssid${NC}"
        if nmcli device wifi connect "$ssid"; then
            echo -e "${GREEN}Successfully connected to $ssid${NC}"
        else
            echo -e "${RED}Failed to connect to $ssid${NC}"
        fi
    else
        # Ask for password for secured network
        echo -e "${YELLOW}Enter password for $ssid:${NC}"
        read -s password
        echo
        
        echo -e "${YELLOW}Connecting to $ssid...${NC}"
        if nmcli device wifi connect "$ssid" password "$password"; then
            echo -e "${GREEN}Successfully connected to $ssid${NC}"
        else
            echo -e "${RED}Failed to connect to $ssid. Please check your password and try again.${NC}"
        fi
    fi
}

# Function to connect to a network by name
connect_by_name() {
    local ssid="$1"
    local password="$2"
    
    # Check if the network exists
    if ! check_network_exists "$ssid"; then
        echo -e "${RED}Network '$ssid' not found.${NC}"
        echo -e "${YELLOW}Available networks:${NC}"
        nmcli -t -f SSID device wifi list | grep -v '^$' | sort | uniq | sed 's/^/- /'
        exit 1
    fi
    
    # Check if we're already connected to this network
    current_connection=$(nmcli -t -f NAME connection show --active | grep "^$ssid$")
    if [ -n "$current_connection" ]; then
        echo -e "${GREEN}Already connected to $ssid${NC}"
        exit 0
    fi
    
    # Check if the network is already configured in NetworkManager
    saved_connection=$(nmcli -t -f NAME connection show | grep "^$ssid$")
    
    if [ -n "$saved_connection" ]; then
        # Connect using the saved connection
        echo -e "${YELLOW}Connecting to saved network: $ssid${NC}"
        if nmcli connection up "$ssid"; then
            echo -e "${GREEN}Successfully connected to $ssid${NC}"
        else
            echo -e "${RED}Failed to connect to $ssid. The saved connection might have issues.${NC}"
        fi
        return
    fi
    
    # Check if the network has security
    security=$(nmcli -t -f SSID,SECURITY device wifi list | grep "^$ssid:" | cut -d ':' -f 2)
    
    # If no password provided but needed, prompt for it
    if [ -z "$password" ] && [ -n "$security" ] && [ "$security" != "--" ]; then
        echo -e "${YELLOW}Network '$ssid' requires a password.${NC}"
        echo -e "${YELLOW}Enter password for $ssid:${NC}"
        read -s password
        echo
    fi
    
    echo -e "${YELLOW}Connecting to $ssid...${NC}"
    
    if [ -z "$password" ]; then
        # Try to connect without password
        if nmcli device wifi connect "$ssid"; then
            echo -e "${GREEN}Successfully connected to $ssid${NC}"
        else
            echo -e "${RED}Failed to connect to $ssid${NC}"
        fi
    else
        # Connect with password
        if nmcli device wifi connect "$ssid" password "$password"; then
            echo -e "${GREEN}Successfully connected to $ssid${NC}"
        else
            echo -e "${RED}Failed to connect to $ssid. Please check your password and try again.${NC}"
        fi
    fi
}

# Main function
main() {
    local list_only=false
    local network_name=""
    local password=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--list)
                list_only=true
                shift
                ;;
            -n|--name)
                if [[ -n "$2" ]]; then
                    network_name="$2"
                    shift 2
                else
                    echo -e "${RED}Error: Argument for $1 is missing${NC}" >&2
                    show_help
                    exit 1
                fi
                ;;
            -p|--password)
                if [[ -n "$2" ]]; then
                    password="$2"
                    shift 2
                else
                    echo -e "${RED}Error: Argument for $1 is missing${NC}" >&2
                    show_help
                    exit 1
                fi
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                show_help
                exit 1
                ;;
        esac
    done
    
    # Handle different modes based on arguments
    if [[ "$list_only" = true ]]; then
        # Only scan and list networks
        scan_networks
    elif [[ -n "$network_name" ]]; then
        # Connect to specified network
        connect_by_name "$network_name" "$password"
    else
        # Interactive mode - scan, list, and prompt for connection
        scan_networks
        
        # Ask for selection
        echo -e "${YELLOW}Select (1-5) to select a network, press Enter to quit:${NC}"
        read choice
        
        # Exit if user just pressed Enter (empty input)
        if [ -z "$choice" ]; then
            echo -e "${GREEN}Exiting.${NC}"
            exit 0
        fi
        
        # Validate choice
        if ! [[ "$choice" =~ ^[1-5]$ ]]; then
            echo -e "${RED}Invalid choice. Please enter a number between 1 and 5.${NC}"
            exit 1
        fi
        
        # Connect to selected network
        connect_to_network "$choice"
    fi
}

# Start the script
main "$@"
