#!/usr/bin/env bash

# Script name: disable-nic-offloading.sh
# Description: Creates a systemd service to disable NIC offloading features

# Color variables
YW="\033[33m"
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
CL="\033[m"

function header_info {
  clear
  cat <<"EOF"
 _   _ ___ ____    ___   __  __ _                 _ _             
| \ | |_ _/ ___|  / _ \ / _|/ _| | ___   __ _  __| (_)_ __   __ _ 
|  \| || | |     | | | | |_| |_| |/ _ \ / _` |/ _` | | '_ \ / _` |
| |\  || | |___  | |_| |  _|  _| | (_) | (_| | (_| | | | | | (_| |
|_| \_|___\____|  \___/|_| |_| |_|\___/ \__,_|\__,_|_|_| |_|\__, |
                                                             |___/ 
 ____  _           _     _           
|  _ \(_)___  __ _| |__ | | ___ _ __ 
| | | | / __|/ _` | '_ \| |/ _ \ '__|
| |_| | \__ \ (_| | |_) | |  __/ |   
|____/|_|___/\__,_|_.__/|_|\___|_|   
                                     
EOF

  echo -e "${BL}NIC Offloading Disabler${CL}"
  echo -e "${YW}This script creates a systemd service to disable NIC offloading features${CL}\n"
}

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RD}Error: This script must be run as root${CL}"
    exit 1
fi

# Check for required commands
if ! command -v whiptail >/dev/null 2>&1; then
    echo -e "${YW}Installing whiptail...${CL}"
    apt-get update &>/dev/null
    apt-get install -y whiptail &>/dev/null || { echo -e "${RD}Failed to install whiptail. Exiting.${CL}"; exit 1; }
fi

if ! command -v ethtool >/dev/null 2>&1; then
    echo -e "${YW}Installing ethtool...${CL}"
    apt-get update &>/dev/null
    apt-get install -y ethtool &>/dev/null || { echo -e "${RD}Failed to install ethtool. Exiting.${CL}"; exit 1; }
fi

header_info

# Get list of network interfaces
INTERFACES=()
while read -r interface; do
    # Skip loopback interface
    if [[ "$interface" != "lo" ]]; then
        INTERFACES+=("$interface" "Network Interface")
    fi
done < <(ls /sys/class/net/)

# Check if any non-loopback interfaces were found
if [ ${#INTERFACES[@]} -eq 0 ]; then
    whiptail --title "Error" --msgbox "No network interfaces found!" 10 50
    echo -e "${RD}No network interfaces found! Exiting.${CL}"
    exit 1
fi

# Show interface selection menu
SELECTED_INTERFACE=$(whiptail --backtitle "NIC Offloading Disabler" --title "Network Interfaces" \
                    --menu "Select a network interface:" 15 60 6 \
                    "${INTERFACES[@]}" 3>&1 1>&2 2>&3)

exitstatus=$?
if [ $exitstatus != 0 ]; then
    echo -e "${RD}User canceled. Exiting.${CL}"
    exit 0
fi

echo -e "${YW}Selected interface: ${BL}$SELECTED_INTERFACE${CL}"

# Create service name
SERVICE_NAME="disable-nic-offload-$SELECTED_INTERFACE.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

# Show confirmation dialog
if ! whiptail --backtitle "NIC Offloading Disabler" --title "Confirmation" \
    --yesno "This will create a systemd service to disable offloading features for $SELECTED_INTERFACE.\n\nProceed?" 12 60; then
    echo -e "${RD}User canceled. Exiting.${CL}"
    exit 0
fi

# Create the service file
echo -e "${YW}Creating systemd service...${CL}"

cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Disable NIC offloading for $SELECTED_INTERFACE
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ethtool -K $SELECTED_INTERFACE gso off gro off tso off tx off rx off rxvlan off txvlan off sg off
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# Check if service file was created successfully
if [ ! -f "$SERVICE_PATH" ]; then
    whiptail --title "Error" --msgbox "Failed to create service file!" 10 50
    echo -e "${RD}Failed to create service file! Exiting.${CL}"
    exit 1
fi

{
    # Progress gauge operations
    echo "10"; sleep 0.2
    echo "25"; sleep 0.2
    
    # Reload systemd to recognize the new service
    systemctl daemon-reload
    echo "50"; sleep 0.2
    
    # Start the service
    systemctl start "$SERVICE_NAME"
    echo "75"; sleep 0.2
    
    # Enable the service to start on boot
    systemctl enable "$SERVICE_NAME"
    echo "100"; sleep 0.2
} | whiptail --backtitle "NIC Offloading Disabler" --gauge "Configuring service..." 10 60 0

# Final status check
if systemctl is-active --quiet "$SERVICE_NAME"; then
    SERVICE_STATUS="Active"
else
    SERVICE_STATUS="Inactive"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    BOOT_STATUS="Enabled"
else
    BOOT_STATUS="Disabled"
fi

# Show results
whiptail --backtitle "NIC Offloading Disabler" --title "Success" --msgbox \
"Service created successfully!\n\nService: $SERVICE_NAME\nStatus: $SERVICE_STATUS\nStart on boot: $BOOT_STATUS\n\nInterface: $SELECTED_INTERFACE" 15 60

echo -e "${GN}Service created and enabled successfully!${CL}"
echo -e "${YW}Service: ${BL}$SERVICE_NAME${CL}"
echo -e "${YW}Status: ${BL}$SERVICE_STATUS${CL}"
echo -e "${YW}Start on boot: ${BL}$BOOT_STATUS${CL}"
echo -e "${YW}Interface: ${BL}$SELECTED_INTERFACE${CL}"

# Optional: Test the service
if whiptail --backtitle "NIC Offloading Disabler" --title "Test Service" \
   --yesno "Would you like to check the current offloading status of $SELECTED_INTERFACE?" 10 60; then
    
    echo -e "\n${YW}Current offloading features for ${BL}$SELECTED_INTERFACE${YW}:${CL}"
    ethtool -k "$SELECTED_INTERFACE" | grep -E 'tcp-segmentation-offload|generic-segmentation-offload|generic-receive-offload|tx-offload|rx-offload|rx-vlan-offload|tx-vlan-offload|scatter-gather'
fi

exit 0
