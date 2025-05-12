#!/usr/bin/env bash

# Script name: disable-nic-offloading.sh
# Description: Creates a systemd service to disable NIC offloading features for Intel e1000e interfaces

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

  echo -e "${BL}Intel e1000e NIC Offloading Disabler${CL}"
  echo -e "${YW}This script creates a systemd service to disable NIC offloading features${CL}"
  echo -e "${YW}for Intel e1000e network interfaces${CL}\n"
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

# Get list of network interfaces using Intel e1000e driver
INTERFACES=()
COUNT=0

echo -e "${YW}Searching for Intel e1000e interfaces...${CL}"

while read -r interface; do
    # Skip loopback interface and virtual interfaces
    if [[ "$interface" != "lo" ]] && [[ ! "$interface" =~ ^(tap|fwbr|veth|vmbr|bonding_masters) ]]; then
        # Check if the interface uses the e1000e driver
        driver=$(basename $(readlink -f /sys/class/net/$interface/device/driver 2>/dev/null) 2>/dev/null)
        
        if [[ "$driver" == "e1000e" ]]; then
            # Get MAC address for additional identification
            mac=$(cat /sys/class/net/$interface/address 2>/dev/null)
            INTERFACES+=("$interface" "Intel e1000e NIC ($mac)")
            ((COUNT++))
        fi
    fi
done < <(ls /sys/class/net/)

# Check if any Intel e1000e interfaces were found
if [ ${#INTERFACES[@]} -eq 0 ]; then
    whiptail --title "Error" --msgbox "No Intel e1000e network interfaces found!" 10 60
    echo -e "${RD}No Intel e1000e network interfaces found! Exiting.${CL}"
    exit 1
fi

echo -e "${GN}Found $COUNT Intel e1000e interfaces${CL}"

# Show interface selection menu
SELECTED_INTERFACE=$(whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --title "Network Interfaces" \
                    --menu "Select an Intel e1000e network interface:" 15 70 6 \
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

# Get interface details for confirmation
SPEED=$(cat /sys/class/net/$SELECTED_INTERFACE/speed 2>/dev/null)
MAC=$(cat /sys/class/net/$SELECTED_INTERFACE/address 2>/dev/null)
IP=$(ip -o -4 addr show $SELECTED_INTERFACE 2>/dev/null | awk '{print $4}')

# Show confirmation dialog with interface details
if ! whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --title "Confirmation" \
    --yesno "Interface: $SELECTED_INTERFACE\nDriver: e1000e\nMAC: $MAC\nIP: $IP\nSpeed: ${SPEED}Mbps\n\nThis will create a systemd service to disable offloading features.\n\nProceed?" 15 70; then
    echo -e "${RD}User canceled. Exiting.${CL}"
    exit 0
fi

# Create the service file with e1000e specific optimizations
echo -e "${YW}Creating systemd service...${CL}"

cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Disable NIC offloading for Intel e1000e interface $SELECTED_INTERFACE
After=network.target

[Service]
Type=oneshot
# Disable all offloading features for Intel e1000e
ExecStart=/sbin/ethtool -K $SELECTED_INTERFACE gso off gro off tso off tx off rx off rxvlan off txvlan off sg off
# Intel e1000e specific: Set interrupt moderation and ring parameters
ExecStart=/sbin/ethtool -C $SELECTED_INTERFACE rx-usecs 3 tx-usecs 3
ExecStart=/sbin/ethtool -G $SELECTED_INTERFACE rx 256 tx 256
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
} | whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --gauge "Configuring service..." 10 60 0

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
whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --title "Success" --msgbox \
"Service created successfully!\n\nService: $SERVICE_NAME\nStatus: $SERVICE_STATUS\nStart on boot: $BOOT_STATUS\n\nInterface: $SELECTED_INTERFACE (Intel e1000e)" 15 70

echo -e "${GN}Service created and enabled successfully!${CL}"
echo -e "${YW}Service: ${BL}$SERVICE_NAME${CL}"
echo -e "${YW}Status: ${BL}$SERVICE_STATUS${CL}"
echo -e "${YW}Start on boot: ${BL}$BOOT_STATUS${CL}"
echo -e "${YW}Interface: ${BL}$SELECTED_INTERFACE${CL}"
echo -e "${YW}Driver: ${BL}e1000e${CL}"

# Optional: Test the service
if whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --title "Test Service" \
   --yesno "Would you like to check the current offloading status of $SELECTED_INTERFACE?" 10 70; then
    
    echo -e "\n${YW}Current offloading features for ${BL}$SELECTED_INTERFACE${YW}:${CL}"
    ethtool -k "$SELECTED_INTERFACE" | grep -E 'tcp-segmentation-offload|generic-segmentation-offload|generic-receive-offload|tx-offload|rx-offload|rx-vlan-offload|tx-vlan-offload|scatter-gather'
    
    echo -e "\n${YW}Current interrupt moderation settings:${CL}"
    ethtool -c "$SELECTED_INTERFACE"
    
    echo -e "\n${YW}Current ring parameters:${CL}"
    ethtool -g "$SELECTED_INTERFACE"
fi

echo -e "\n${GN}Intel e1000e optimization complete!${CL}"

exit 0
