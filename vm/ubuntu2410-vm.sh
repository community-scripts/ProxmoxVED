#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}"
source /dev/stdin <<<$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/api.func")

function header_info {
    clear
    cat <<"EOF"
   __  ____                __           ___  __ __   _______     _    ____  ___
  / / / / /_  __  ______  / /___  __   |__ \/ // /  <  / __ \   | |  / /  |/  /
 / / / / __ \/ / / / __ \/ __/ / / /   __/ / // /_  / / / / /   | | / / /|_/ /
/ /_/ / /_/ / /_/ / / / / /_/ /_/ /   / __/__  __/ / / /_/ /    | |/ / /  / /
\____/_.___/\__,_/_/ /_/\__/\__,_/   /____/ /_/ (_)_/\____/     |___/_/  /_/  (Oracular Oriole)

EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
APP="Ubuntu 24.10 VM"
NSAPP="ubuntu-2410-vm"
var_os="ubuntu"
var_version="2410"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "

CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
OS="${TAB}🖥️${TAB}${CL}"
CONTAINERTYPE="${TAB}📦${TAB}${CL}"
DISKSIZE="${TAB}💾${TAB}${CL}"
CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"
CONTAINERID="${TAB}🆔${TAB}${CL}"
HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"
GATEWAY="${TAB}🌐${TAB}${CL}"
DEFAULT="${TAB}⚙️${TAB}${CL}"
MACADDRESS="${TAB}🔗${TAB}${CL}"
VLANTAG="${TAB}🏷️${TAB}${CL}"
CREATING="${TAB}🚀${TAB}${CL}"
ADVANCED="${TAB}🧩${TAB}${CL}"

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM
function error_handler() {
    local exit_code="$?"
    local line_number="$1"
    local command="$2"
    post_update_to_api "failed" "$command"
    local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
    echo -e "\n$error_message\n"
    cleanup_vmid
}

function get_valid_nextid() {
    local try_id
    try_id=$(pvesh get /cluster/nextid)
    while true; do
        if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
            try_id=$((try_id + 1))
            continue
        fi
        if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
            try_id=$((try_id + 1))
            continue
        fi
        break
    done
    echo "$try_id"
}

function cleanup_vmid() {
    if qm status $VMID &>/dev/null; then
        qm stop $VMID &>/dev/null
        qm destroy $VMID &>/dev/null
    fi
}

function cleanup() {
    popd >/dev/null
    rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "$APP" --yesno "This will create a New $APP. Proceed?" 10 58; then
    :
else
    header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function msg_info() {
    local msg="$1"
    echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
}

function msg_ok() {
    local msg="$1"
    echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

function msg_error() {
    local msg="$1"
    echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

function check_root() {
    if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
        clear
        msg_error "Please run this script as root."
        echo -e "\nExiting..."
        sleep 2
        exit
    fi
}

function pve_check() {
    if ! pveversion | grep -Eq "pve-manager/(8\.[1-4]|9\.[0-1])(\.[0-9]+)*"; then
        msg_error "${CROSS}${RD}This version of Proxmox Virtual Environment is not supported"
        echo -e "Requires Proxmox Virtual Environment Version 8.1 - 8.4 or 9.0 - 9.1."
        echo -e "Exiting..."
        sleep 2
        exit
    fi
}

function arch_check() {
    if [ "$(dpkg --print-architecture)" != "amd64" ]; then
        echo -e "\n ${INFO}${YWB}This script will not work with PiMox! \n"
        echo -e "\n ${YWB}Visit https://github.com/asylumexp/Proxmox for ARM64 support. \n"
        echo -e "Exiting..."
        sleep 2
        exit
    fi
}

function ssh_check() {
    if command -v pveversion >/dev/null 2>&1; then
        if [ -n "${SSH_CLIENT:+x}" ]; then
            if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
                echo "you've been warned"
            else
                clear
                exit
            fi
        fi
    fi
}

function exit-script() {
    clear
    echo -e "\n${CROSS}${RD}User exited script${CL}\n"
    exit
}

function init_settings() {
    VMID="$(get_valid_nextid)"
    HN="ubuntu"
    DISK_SIZE="8G"
    DISK_CACHE=""
    DISK_EXT=".qcow2"
    DISK_REF="$VMID/"
    CPU_TYPE=""
    CORE_COUNT="2"
    RAM_SIZE="2048"
    MACHINE_TYPE="i440fx"
    MACHINE=""
    FORMAT=",efitype=4m"
    BRG="vmbr0"
    MAC="$GEN_MAC"
    VLAN=""
    MTU=""
    START_VM="yes"
}

function default_settings() {
    METHOD="default"
    echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
    echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
    echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
    echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
    echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}${DISK_CACHE:-None}${CL}"
    echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}${MACHINE_TYPE}${CL}"
    echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
    echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
    echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}${var_vlan:-Default}${CL}"
    echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}${var_mtu:-Default}${CL}"
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}${START_VM}${CL}"
    echo -e "${CREATING}${BOLD}${DGN}Creating a $APP using default settings${CL}"
}

function apply_env_overrides() {
    METHOD="env"
    [ -n "$var_vmid" ] && VMID="$var_vmid"
    HN=$(echo "${var_hostname,,}" | tr -cd '[:alnum:]-')
    [[ -z "$HN" ]] && HN="ubuntu"
    [[ ! "$HN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && {
        msg_error "Invalid hostname: $HN"
        exit 1
    }

    case "$var_machine" in
    q35)
        MACHINE_TYPE="q35"
        FORMAT=""
        MACHINE=" -machine q35"
        ;;
    *)
        MACHINE_TYPE="i440fx"
        FORMAT=",efitype=4m"
        MACHINE=""
        ;;
    esac

    case "$var_cpu_type" in
    1) CPU_TYPE=" -cpu host" ;;
    *) CPU_TYPE="" ;;
    esac

    case "$var_disk_cache" in
    1) DISK_CACHE="cache=writethrough," ;;
    *) DISK_CACHE="" ;;
    esac

    [[ "$var_cpu" =~ ^[1-9][0-9]*$ ]] && CORE_COUNT="$var_cpu" || CORE_COUNT="2"
    [[ "$var_ram" =~ ^[1-9][0-9]*$ ]] && RAM_SIZE="$var_ram" || RAM_SIZE="2048"
    [[ -n "$var_disk" ]] && DISK_SIZE="$var_disk" || DISK_SIZE="8G"
    [ -n "$var_bridge" ] && BRG="$var_bridge"
    [ -z "$BRG" ] && BRG="vmbr0"

    [ -n "$var_mac" ] && MAC="$var_mac"
    [ -z "$MAC" ] && MAC="$GEN_MAC"
    VLAN=${var_vlan:+",tag=$var_vlan"}
    MTU=${var_mtu:+",mtu=$var_mtu"}
    START_VM="$var_start_vm"

    echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
    echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}${MACHINE_TYPE}${CL}"
    echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
    echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}${DISK_CACHE:-None}${CL}"
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
    echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}${CPU_TYPE:+Host}${CPU_TYPE:-KVM64}${CL}"
    echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
    echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
    echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
    echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
    echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}${var_vlan:-Default}${CL}"
    echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}${var_mtu:-Default}${CL}"
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}${START_VM}${CL}"
    echo -e "${CREATING}${BOLD}${DGN}Creating a $APP using environment settings${CL}"
}

function validate_env_settings() {
    [[ -n "$var_hostname" ]] && {
        HN_CLEANED=$(echo "$var_hostname" | tr -cd '[:alnum:]-')
        if [[ ! "$HN_CLEANED" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
            msg_error "Invalid hostname: $var_hostname"
            exit 1
        fi
    }

    [[ -n "$var_vmid" && ! "$var_vmid" =~ ^[1-9][0-9]{2,}$ ]] && {
        msg_error "Invalid VMID: must be a number >= 100"
        exit 1
    }

    [[ -n "$var_cpu" && ! "$var_cpu" =~ ^[1-9][0-9]*$ ]] && {
        msg_error "Invalid CPU core count: must be > 0"
        exit 1
    }

    [[ -n "$var_ram" && ! "$var_ram" =~ ^[1-9][0-9]*$ ]] && {
        msg_error "Invalid RAM size: must be > 0"
        exit 1
    }

    [[ -n "$var_disk" && ! "$var_disk" =~ ^[1-9][0-9]*G$ ]] && {
        msg_error "Invalid disk size: must be like 10G"
        exit 1
    }

    [[ -n "$var_mac" && ! "$var_mac" =~ ^([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$ ]] && {
        msg_error "Invalid MAC address: $var_mac"
        exit 1
    }

    [[ -n "$var_mtu" && ! "$var_mtu" =~ ^[1-9][0-9]{2,4}$ ]] && {
        msg_error "Invalid MTU value: $var_mtu"
        exit 1
    }

    [[ -n "$var_vlan" && ! "$var_vlan" =~ ^[0-9]{1,4}$ ]] && {
        msg_error "Invalid VLAN tag: must be numeric"
        exit 1
    }

    [[ -n "$var_start_vm" && ! "$var_start_vm" =~ ^(yes|no)$ ]] && {
        msg_error "var_start_vm must be 'yes' or 'no'"
        exit 1
    }
}

function advanced_settings() {
    METHOD="advanced"
    [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
    while true; do
        if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
            if [ -z "$VMID" ]; then
                VMID=$(get_valid_nextid)
            fi
            if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
                echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
                sleep 2
                continue
            fi
            echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
            break
        else
            exit-script
        fi
    done

    if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
        "i440fx" "Machine i440fx" ON \
        "q35" "Machine q35" OFF \
        3>&1 1>&2 2>&3); then
        if [ $MACH = q35 ]; then
            echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
            FORMAT=""
            MACHINE=" -machine q35"
        else
            echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
            FORMAT=",efitype=4m"
            MACHINE=""
        fi
    else
        exit-script
    fi

    if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 10, 20)" 8 58 "$DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
        if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
            DISK_SIZE="${DISK_SIZE}G"
            echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
        elif [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
            echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
        else
            echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size. Please use a number (e.g., 10 or 10G).${CL}"
            exit-script
        fi
    else
        exit-script
    fi

    if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
        "0" "None (Default)" ON \
        "1" "Write Through" OFF \
        3>&1 1>&2 2>&3); then
        if [ $DISK_CACHE = "1" ]; then
            echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}Write Through${CL}"
            DISK_CACHE="cache=writethrough,"
        else
            echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
            DISK_CACHE=""
        fi
    else
        exit-script
    fi

    if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 ubuntu --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$VM_NAME" ]; then
            HN="ubuntu"
        else
            HN=$(echo "${VM_NAME,,}" | tr -cd '[:alnum:]-')
        fi
        if [[ ! "$HN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
            msg_error "Invalid hostname: $HN. Must be 1–63 chars, alphanumeric or hyphen, and not start/end with hyphen."
            exit-script
        fi
        echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    else
        exit-script
    fi

    if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
        "0" "KVM64 (Default)" ON \
        "1" "Host" OFF \
        3>&1 1>&2 2>&3); then
        if [ "$CPU_TYPE1" = "1" ]; then
            echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
            CPU_TYPE=" -cpu host"
        else
            echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
            CPU_TYPE=""
        fi
    else
        exit-script
    fi

    if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        CORE_COUNT=$(echo "$CORE_COUNT" | tr -cd '[:digit:]')
        if [[ ! "$CORE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
            msg_error "CPU core count must be a positive integer."
            exit-script
        fi
        echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    else
        exit-script
    fi

    if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 2048 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        RAM_SIZE=$(echo "$RAM_SIZE" | tr -cd '[:digit:]')
        if [[ ! "$RAM_SIZE" =~ ^[1-9][0-9]*$ ]]; then
            msg_error "RAM size must be a positive integer (in MiB)."
            exit-script
        fi
        echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
    else
        exit-script
    fi

    if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z $BRG ]; then
            BRG="vmbr0"
            echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
        else
            echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
        fi
    else
        exit-script
    fi

    if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z $MAC1 ]; then
            MAC="$GEN_MAC"
            echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
        else
            MAC="$MAC1"
            echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC1${CL}"
        fi
    else
        exit-script
    fi

    if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z $VLAN1 ]; then
            VLAN1="Default"
            VLAN=""
            echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
        else
            VLAN=",tag=$VLAN1"
            echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
        fi
    else
        exit-script
    fi

    if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z $MTU1 ]; then
            MTU1="Default"
            MTU=""
            echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
        else
            MTU=",mtu=$MTU1"
            echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
        fi
    else
        exit-script
    fi

    if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
        echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
        START_VM="yes"
    else
        echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
        START_VM="no"
    fi

    if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a $APP?" --no-button Do-Over 10 58); then
        echo -e "${CREATING}${BOLD}${DGN}Creating a $APP using the above advanced settings${CL}"
    else
        header_info
        echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
        advanced_settings
    fi
}

function has_env_overrides() {
    env | grep -qE "^var_(bridge|cpu|cpu_type|disk|disk_cache|hostname|mac|machine|mtu|ram|start_vm|vlan|vmid)="
}

function start_script() {
    header_info
    init_settings
    if has_env_overrides; then
        echo -e "${ADVANCED}${BOLD}${BL}Using Environment Variable Overrides${CL}"
        METHOD="env"
        apply_env_overrides
    elif (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
        echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
        default_settings
    else
        echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
        advanced_settings
    fi
}

check_root
arch_check
pve_check
ssh_check
start_script
post_to_api_vm

msg_info "Validating Storage"
while read -r line; do
    TAG=$(echo $line | awk '{print $1}')
    TYPE=$(echo $line | awk '{printf "%-10s", $2}')
    FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
    ITEM="  Type: $TYPE Free: $FREE "
    OFFSET=2
    if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
        MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
    fi
    STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
    msg_error "Unable to detect a valid storage location."
    exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
    STORAGE=${STORAGE_MENU[0]}
else
    while [ -z "${STORAGE:+x}" ]; do
        STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
            "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
            16 $(($MSG_MAX_LENGTH + 23)) 6 \
            "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
    done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the Ubuntu 24.10 Disk Image"
URL=https://cloud-images.ubuntu.com/oracular/current/oracular-server-cloudimg-amd64.img
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir | cifs)
    DISK_EXT=".qcow2"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format qcow2"
    THIN=""
    ;;
btrfs)
    DISK_EXT=".raw"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format raw"
    FORMAT=",efitype=4m"
    THIN=""
    ;;
esac
for i in {0,1}; do
    disk="DISK$i"
    eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
    eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

msg_info "Creating a $APP"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
    -name $HN -tags "community-script;ubuntu" -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
if [[ "$STORAGE_TYPE" != "lvmthin" ]]; then
    pvesm alloc $STORAGE $VMID $DISK0 4M >/dev/null
fi
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
    -ide2 ${STORAGE}:cloudinit \
    -boot order=scsi0 \
    -serial0 socket \
    -smbios1 type=1 \
    --ciuser "ubuntu" -cipassword "ubuntu" >/dev/null
DESCRIPTION=$(
    cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>$APP</h2>

  <p style='margin: 16px 0;'>
    <a href='https://ko-fi.com/community_scripts' target='_blank' rel='noopener noreferrer'>
      <img src='https://img.shields.io/badge/&#x2615;-Buy us a coffee-blue' alt='spend Coffee' />
    </a>
  </p>

  <span style='margin: 0 10px;'>
    <i class="fa fa-github fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>GitHub</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-comments fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE/discussions' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Discussions</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-exclamation-circle fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE/issues' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Issues</a>
  </span>
</div>
EOF
)
qm set "$VMID" -description "$DESCRIPTION" >/dev/null
if [ -n "$DISK_SIZE" ]; then
    msg_info "Resizing disk to $DISK_SIZE GB"
    qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
    msg_ok "Resized disk to ${CL}${BL}${DISK_SIZE}${CL} GB"
else
    msg_info "Using default disk size of $DEFAULT_DISK_SIZE GB"
    qm resize $VMID scsi0 ${DEFAULT_DISK_SIZE} >/dev/null
    msg_ok "Resized disk to ${CL}${BL}${DEFAULT_DISK_SIZE}${CL} GB"
fi

msg_ok "Created a $APP ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
    msg_info "Starting $APP"
    qm start $VMID
    msg_ok "Started $APP"
fi
post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"
echo -e "Setup Cloud-Init before starting \n
More info at https://github.com/community-scripts/ProxmoxVE/discussions/272 \n"
