#!/usr/bin/env bash

# Creates a systemd service to disable NIC offloading features for Intel e1000e interfaces
# Author: rcastley
# License: MIT

YW=$(echo "\033[33m")
YWB=$'\e[93m'
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
TAB="  "
CM="${TAB}✔️${TAB}"
CROSS="${TAB}✖️${TAB}"
INFO="${TAB}ℹ️${TAB}${CL}"
WARN="${TAB}⚠️${TAB}${CL}"

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
}

header_info

function msg_info() { echo -e "${INFO} ${YW}${1}...${CL}"; }
function msg_ok() { echo -e "${CM} ${GN}${1}${CL}"; }
function msg_error() { echo -e "${CROSS} ${RD}${1}${CL}"; }
function msg_warn() { echo -e "${WARN} ${YWB}${1}"; }

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    msg_error "Error: This script must be run as root."
    exit 1
fi

if ! command -v ethtool >/dev/null 2>&1; then
    msg_info "Installing ethtool"
    apt-get update &>/dev/null
    apt-get install -y ethtool &>/dev/null || { msg_error "Failed to install ethtool. Exiting."; exit 1; }
    msg_ok "ethtool installed successfully"
fi

# Get list of network interfaces using Intel e1000e driver
INTERFACES=()
COUNT=0

msg_info "Searching for Intel e1000e interfaces"

for device in /sys/class/net/*; do
    interface="$(basename "$device")"  # or adjust the rest of the usages below, as mostly you'll use the path anyway
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
done

# Check if any Intel e1000e interfaces were found
if [ ${#INTERFACES[@]} -eq 0 ]; then
    whiptail --title "Error" --msgbox "No Intel e1000e network interfaces found!" 10 60
    msg_error "No Intel e1000e network interfaces found! Exiting."
    exit 1
fi

msg_ok "Found ${BL}$COUNT${GN} Intel e1000e interfaces"

# Create a checklist for interface selection with all interfaces initially checked
INTERFACES_CHECKLIST=()
for ((i=0; i<${#INTERFACES[@]}; i+=2)); do
    INTERFACES_CHECKLIST+=("${INTERFACES[i]}" "${INTERFACES[i+1]}" "ON")
done

# Show interface selection checklist
SELECTED_INTERFACES=$(whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --title "Network Interfaces" \
                    --separate-output --checklist "Select Intel e1000e network interfaces\n(Space to toggle, Enter to confirm):" 15 80 6 \
                    "${INTERFACES_CHECKLIST[@]}" 3>&1 1>&2 2>&3)

exitstatus=$?
if [ $exitstatus != 0 ]; then
    msg_info "User canceled. Exiting."
    exit 0
fi

# Check if any interfaces were selected
if [ -z "$SELECTED_INTERFACES" ]; then
    msg_error "No interfaces selected. Exiting."
    exit 0
fi

# Convert the selected interfaces into an array
readarray -t INTERFACE_ARRAY <<< "$SELECTED_INTERFACES"

# Show the number of selected interfaces
INTERFACE_COUNT=${#INTERFACE_ARRAY[@]}

# Print selected interfaces
for iface in "${INTERFACE_ARRAY[@]}"; do
    msg_ok "Selected interface: ${BL}$iface${CL}"
done

# Ask for confirmation with the list of selected interfaces
CONFIRMATION_MSG="You have selected the following interface(s):\n\n"
for iface in "${INTERFACE_ARRAY[@]}"; do
    SPEED=$(cat /sys/class/net/$iface/speed 2>/dev/null)
    MAC=$(cat /sys/class/net/$iface/address 2>/dev/null)
    CONFIRMATION_MSG+="- $iface (MAC: $MAC, Speed: ${SPEED}Mbps)\n"
done
CONFIRMATION_MSG+="\nThis will create systemd service(s) to disable offloading features.\n\nProceed?"

if ! whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --title "Confirmation" \
    --yesno "$CONFIRMATION_MSG" 20 80; then
    msg_info "User canceled. Exiting."
    exit 0
fi

# Ask if rx/tx optimization should be performed
if whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --title "RX/TX Optimization" \
    --yesno "Would you like to apply RX/TX interrupt moderation and ring buffer optimizations?\n\nThese settings can improve network performance for Intel e1000e NICs by adjusting:\n- Interrupt moderation (rx-usecs, tx-usecs)\n- Ring buffer sizes (rx, tx)" 15 80; then
    APPLY_RXTX_OPTIMIZATION=true
else
    APPLY_RXTX_OPTIMIZATION=false
fi

# Loop through all selected interfaces and create services for each
for SELECTED_INTERFACE in "${INTERFACE_ARRAY[@]}"; do
    # Create service name for this interface
    SERVICE_NAME="disable-nic-offload-$SELECTED_INTERFACE.service"
    SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

    # Create the service file with e1000e specific optimizations
    msg_info "Creating systemd service for interface: ${BL}$SELECTED_INTERFACE${YW}"

    # Start with the common part of the service file
    cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Disable NIC offloading for Intel e1000e interface $SELECTED_INTERFACE
After=network.target

[Service]
Type=oneshot
# Disable all offloading features for Intel e1000e
ExecStart=/sbin/ethtool -K $SELECTED_INTERFACE gso off gro off tso off tx off rx off rxvlan off txvlan off sg off
EOF

    # Add RX/TX optimization if selected
    if [ "$APPLY_RXTX_OPTIMIZATION" = true ]; then
        cat >> "$SERVICE_PATH" << EOF
# Intel e1000e specific: Set interrupt moderation and ring parameters
ExecStart=/sbin/ethtool -C $SELECTED_INTERFACE rx-usecs 3 tx-usecs 3
ExecStart=/sbin/ethtool -G $SELECTED_INTERFACE rx 256 tx 256
EOF
    fi

    # Complete the service file
    cat >> "$SERVICE_PATH" << EOF
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

    # Check if service file was created successfully
    if [ ! -f "$SERVICE_PATH" ]; then
        whiptail --title "Error" --msgbox "Failed to create service file for $SELECTED_INTERFACE!" 10 50
        msg_error "Failed to create service file for $SELECTED_INTERFACE! Skipping to next interface."
        continue
    fi

    # Configure this service
    {
        echo "25"; sleep 0.1
        # Reload systemd to recognize the new service
        systemctl daemon-reload
        echo "50"; sleep 0.1
        # Start the service
        systemctl start "$SERVICE_NAME"
        echo "75"; sleep 0.1
        # Enable the service to start on boot
        systemctl enable "$SERVICE_NAME"
        echo "100"; sleep 0.1
    } | whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --gauge "Configuring service for $SELECTED_INTERFACE..." 10 80 0

    # Individual service status
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

    # Show individual service results
    msg_ok "Service for ${BL}$SELECTED_INTERFACE${GN} created and enabled!"
    msg_info "${TAB}Service: ${BL}$SERVICE_NAME${YW}"
    msg_info "${TAB}Status: ${BL}$SERVICE_STATUS${YW}"
    msg_info "${TAB}Start on boot: ${BL}$BOOT_STATUS${YW}"
done

# Prepare RX/TX optimization status for display
if [ "$APPLY_RXTX_OPTIMIZATION" = true ]; then
    RXTX_STATUS="Applied"
else
    RXTX_STATUS="Not Applied"
fi

# Prepare summary of all interfaces
SUMMARY_MSG="Services created successfully!\n\n"
SUMMARY_MSG+="RX/TX Optimization: $RXTX_STATUS\n\n"
SUMMARY_MSG+="Configured Interfaces:\n"

for iface in "${INTERFACE_ARRAY[@]}"; do
    SERVICE_NAME="disable-nic-offload-$iface.service"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        SVC_STATUS="Active"
    else
        SVC_STATUS="Inactive"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        BOOT_SVC_STATUS="Enabled"
    else
        BOOT_SVC_STATUS="Disabled"
    fi

    SUMMARY_MSG+="- $iface: $SVC_STATUS, Boot: $BOOT_SVC_STATUS\n"
done

# Show summary results
whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --title "Success" --msgbox "$SUMMARY_MSG" 20 80


msg_info "RX/TX Optimization: ${BL}$RXTX_STATUS${YW}"
# for iface in "${INTERFACE_ARRAY[@]}"; do
#     echo -e "\n${YW}Interface: ${BL}$iface${CL}"
#     echo -e "${YW}Driver: ${BL}e1000e${CL}"
#     SERVICE_NAME="disable-nic-offload-$iface.service"
#     if systemctl is-active --quiet "$SERVICE_NAME"; then
#         echo -e "${YW}Status: ${BL}Active${CL}"
#     else
#         echo -e "${YW}Status: ${BL}Inactive${CL}"
#     fi

#     if systemctl is-enabled --quiet "$SERVICE_NAME"; then
#         echo -e "${YW}Start on boot: ${BL}Enabled${CL}"
#     else
#         echo -e "${YW}Start on boot: ${BL}Disabled${CL}"
#     fi
# done

# Optional: Test the services
# if whiptail --backtitle "Intel e1000e NIC Offloading Disabler" --title "Test Services" \
#    --yesno "Would you like to check the current offloading status of the configured interfaces?" 10 80; then

#     for iface in "${INTERFACE_ARRAY[@]}"; do
#         echo -e "\n${YW}======= ${BL}$iface${YW} =======${CL}"
#         msg_info "Current offloading features for ${BL}$iface${YW}:"
#         ethtool -k "$iface" | grep -E 'tcp-segmentation-offload|generic-segmentation-offload|generic-receive-offload|tx-offload|rx-offload|rx-vlan-offload|tx-vlan-offload|scatter-gather'

#         if [ "$APPLY_RXTX_OPTIMIZATION" = true ]; then
#             msg_info "Current interrupt moderation settings for ${BL}$iface${YW}:"
#             ethtool -c "$iface"

#             msg_info "Current ring parameters for ${BL}$iface${YW}:"
#             ethtool -g "$iface"
#         fi
#     done
# fi

msg_ok "Intel e1000e optimization complete for ${#INTERFACE_ARRAY[@]} interface(s)!"

exit 0
