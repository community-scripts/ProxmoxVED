#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: thost96 (thost96) | Co-Author: michelroegl-brunner
# Refactor (q35 + PVE9 virt-customize network fix + robustness): MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

set -e
source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)

function header_info() {
    clear
    cat <<"EOF"
    ____             __                _    ____  ___
   / __ \____  _____/ /_____  _____   | |  / /  |/  /
  / / / / __ \/ ___/ //_/ _ \/ ___/   | | / / /|_/ /
 / /_/ / /_/ / /__/ ,< /  __/ /       | |/ / /  / /
/_____/\____/\___/_/|_|\___/_/        |___/_/  /_/

EOF
}
header_info
echo -e "\n Loading..."

# ---------- Globals ----------
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="docker-vm"
var_os="debian"
var_version="12"
DISK_SIZE="10G"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
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
CLOUD="${TAB}☁️${TAB}${CL}"

THIN="discard=on,ssd=1,"

trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM

function error_handler() {
    local exit_code="$?"
    local line_number="$1"
    local command="$2"
    local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
    post_update_to_api "failed" "${command}"
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
        qm stop $VMID &>/dev/null || true
        qm destroy $VMID &>/dev/null || true
    fi
}

function cleanup() {
    popd >/dev/null || true
    post_update_to_api "done" "none"
    rm -rf "$TEMP_DIR"
}

TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null

if ! whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker VM" --yesno "This will create a New Docker VM. Proceed?" 10 58; then
    header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function msg_info() { echo -ne "${TAB}${YW}${HOLD}$1${HOLD}"; }
function msg_ok() { echo -e "${BFR}${CM}${GN}$1${CL}"; }
function msg_error() { echo -e "${BFR}${CROSS}${RD}$1${CL}"; }

function check_root() {
    if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
        clear
        msg_error "Please run this script as root."
        echo -e "\nExiting..."
        sleep 2
        exit
    fi
}

# Supported: Proxmox VE 8.0.x – 8.9.x and 9.0 (NOT 9.1+)
pve_check() {
    local PVE_VER
    PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"
    if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]]; then
        local MINOR="${BASH_REMATCH[1]}"
        ((MINOR >= 0 && MINOR <= 9)) && return 0
        msg_error "This version of Proxmox VE is not supported."
        exit 1
    fi
    if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
        local MINOR="${BASH_REMATCH[1]}"
        ((MINOR == 0)) && return 0
        msg_error "This version of Proxmox VE is not yet supported (9.1+)."
        exit 1
    fi
    msg_error "This version of Proxmox VE is not supported (need 8.x or 9.0)."
    exit 1
}

function arch_check() {
    if [ "$(dpkg --print-architecture)" != "amd64" ]; then
        echo -e "\n ${INFO}This script will not work with PiMox! \n"
        echo -e "\n Visit https://github.com/asylumexp/Proxmox for ARM64 support. \n"
        echo -e "Exiting..."
        sleep 2
        exit
    fi
}

function ssh_check() {
    if command -v pveversion >/dev/null 2>&1 && [ -n "${SSH_CLIENT:+x}" ]; then
        if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Proceed anyway?" 10 62; then :; else
            clear
            exit
        fi
    fi
}

function exit-script() {
    clear
    echo -e "\n${CROSS}${RD}User exited script${CL}\n"
    exit
}

function default_settings() {
    VMID=$(get_valid_nextid)
    FORMAT=",efitype=4m"
    DISK_CACHE=""
    DISK_SIZE="10G"
    HN="docker"
    CPU_TYPE=""
    CORE_COUNT="2"
    RAM_SIZE="4096"
    BRG="vmbr0"
    MAC="$GEN_MAC"
    VLAN=""
    MTU=""
    START_VM="yes"
    METHOD="default"
    echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
    echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}q35${CL}"
    echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
    echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
    echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
    echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
    echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
    echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
    echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
    echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
    echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM using the above default settings${CL}"
}

function advanced_settings() {
    METHOD="advanced"
    [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
    while true; do
        if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
            [ -z "$VMID" ] && VMID=$(get_valid_nextid)
            if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
                echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
                sleep 2
                continue
            fi
            echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
            break
        else exit-script; fi
    done

    FORMAT=",efitype=4m"
    echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}q35${CL}"

    if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 10, 20)" 8 58 "$DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
        if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then DISK_SIZE="${DISK_SIZE}G"; fi
        [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]] || {
            echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size.${CL}"
            exit-script
        }
        echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    else exit-script; fi

    if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
        "0" "None (Default)" ON "1" "Write Through" OFF 3>&1 1>&2 2>&3); then
        if [ "$DISK_CACHE" = "1" ]; then
            DISK_CACHE="cache=writethrough,"
            echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}Write Through${CL}"
        else
            DISK_CACHE=""
            echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
        fi
    else exit-script; fi

    if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 docker --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$VM_NAME" ]; then HN="docker"; else HN=$(echo ${VM_NAME,,} | tr -d ' '); fi
        echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    else exit-script; fi

    if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
        "0" "KVM64 (Default)" ON "1" "Host" OFF 3>&1 1>&2 2>&3); then
        if [ "$CPU_TYPE1" = "1" ]; then
            CPU_TYPE=" -cpu host"
            echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
        else
            CPU_TYPE=""
            echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
        fi
    else exit-script; fi

    if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        [ -z "$CORE_COUNT" ] && CORE_COUNT="2"
        echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    else exit-script; fi

    if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 2048 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        [ -z "$RAM_SIZE" ] && RAM_SIZE="2048"
        echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
    else exit-script; fi

    if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        [ -z "$BRG" ] && BRG="vmbr0"
        echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    else exit-script; fi

    if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$MAC1" ]; then MAC="$GEN_MAC"; else MAC="$MAC1"; fi
        echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
    else exit-script; fi

    if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$VLAN1" ]; then
            VLAN1="Default"
            VLAN=""
        else VLAN=",tag=$VLAN1"; fi
        echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
    else exit-script; fi

    if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$MTU1" ]; then
            MTU1="Default"
            MTU=""
        else MTU=",mtu=$MTU1"; fi
        echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
    else exit-script; fi

    if whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58; then
        echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
        START_VM="yes"
    else
        echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
        START_VM="no"
    fi

    if whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Docker VM?" --no-button Do-Over 10 58; then
        echo -e "${CREATING}${BOLD}${DGN}Creating a Docker VM using the above advanced settings${CL}"
    else
        header_info
        echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
        advanced_settings
    fi
}

function start_script() {
    if whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58; then
        header_info
        echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
        default_settings
    else
        header_info
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

function choose_os() {
    if OS_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
        --title "Choose Base OS" \
        --radiolist "Select the OS for the Docker VM:" 12 60 3 \
        "debian12" "Debian 12 (Bookworm, stable & best for scripts)" ON \
        "debian13" "Debian 13 (Trixie, newer, but repos lag)" OFF \
        "ubuntu24" "Ubuntu 24.04 LTS (modern kernel, GPU/AI friendly)" OFF \
        3>&1 1>&2 2>&3); then
        case "$OS_CHOICE" in
        debian12)
            var_os="debian"
            var_version="12"
            URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-$(dpkg --print-architecture).qcow2"
            ;;
        debian13)
            var_os="debian"
            var_version="13"
            URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-$(dpkg --print-architecture).qcow2"
            ;;
        ubuntu24)
            var_os="ubuntu"
            var_version="24.04"
            URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-$(dpkg --print-architecture).img"
            ;;
        esac
        echo -e "${OS}${BOLD}${DGN}Selected OS: ${BGN}${OS_CHOICE}${CL}"
    else
        exit-script
    fi
}

PVE_VER=$(pveversion | awk -F'/' '{print $2}' | cut -d'-' -f1 | cut -d'.' -f1)
if [ "$PVE_VER" -eq 8 ]; then
    INSTALL_MODE="direct"
elif [ "$PVE_VER" -eq 9 ]; then
    INSTALL_MODE="firstboot"
else
    msg_error "Unsupported Proxmox VE version: $PVE_VER"
    exit 1
fi

# ---------- Storage selection ----------
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

# ---------- Download Cloud Image ----------
choose_os
msg_info "Retrieving Cloud Image for $var_os $var_version"
curl --retry 30 --retry-delay 3 --retry-connrefused -fSL -o "$(basename "$URL")" "$URL"
FILE=$(basename "$URL")
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# Ubuntu RAW → qcow2
if [[ "$FILE" == *.img ]]; then
    msg_info "Converting RAW image to qcow2"
    qemu-img convert -O qcow2 "$FILE" "${FILE%.img}.qcow2"
    rm -f "$FILE"
    FILE="${FILE%.img}.qcow2"
    msg_ok "Converted to ${CL}${BL}${FILE}${CL}"
fi

# ---------- Ensure libguestfs-tools ----------
if ! command -v virt-customize &>/dev/null; then
    msg_info "Installing libguestfs-tools on host"
    apt-get -qq update >/dev/null
    apt-get -qq install -y libguestfs-tools lsb-release >/dev/null
    msg_ok "Installed libguestfs-tools"
fi

# ---------- Decide distro codename & Docker repo base ----------
if [[ "$URL" == *"/bookworm/"* || "$FILE" == *"debian-12-"* ]]; then
    CODENAME="bookworm"
    DOCKER_BASE="https://download.docker.com/linux/debian"
elif [[ "$URL" == *"/trixie/"* || "$FILE" == *"debian-13-"* ]]; then
    CODENAME="trixie"
    DOCKER_BASE="https://download.docker.com/linux/debian"
elif [[ "$URL" == *"/noble/"* || "$FILE" == *"noble-"* ]]; then
    CODENAME="noble"
    DOCKER_BASE="https://download.docker.com/linux/ubuntu"
else
    CODENAME="bookworm"
    DOCKER_BASE="https://download.docker.com/linux/debian"
fi
# Map Debian trixie → bookworm (Docker-Repo oft später)
REPO_CODENAME="$CODENAME"
if [[ "$DOCKER_BASE" == *"linux/debian"* && "$CODENAME" == "trixie" ]]; then
    REPO_CODENAME="bookworm"
fi

# ---------- Detect PVE major version (again; independent var) ----------
PVE_MAJ=$(pveversion | awk -F'/' '{print $2}' | cut -d'-' -f1 | cut -d'.' -f1)
if [ "$PVE_MAJ" -eq 8 ]; then INSTALL_MODE="direct"; else INSTALL_MODE="firstboot"; fi

# ---------- Optional: allow manual override ----------
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker Installation Mode" \
    --yesno "Detected PVE ${PVE_MAJ}. Use ${INSTALL_MODE^^} mode?\n\nYes = ${INSTALL_MODE^^}\nNo  = Switch to the other mode" 11 70; then :; else
    if [ "$INSTALL_MODE" = "direct" ]; then INSTALL_MODE="firstboot"; else INSTALL_MODE="direct"; fi
fi

# ---------- PVE8: Direct install into image via virt-customize ----------
if [ "$INSTALL_MODE" = "direct" ]; then
    msg_info "Injecting Docker directly into image (${CODENAME}, $(basename "$DOCKER_BASE"))"
    virt-customize -q -a "${FILE}" \
        --install qemu-guest-agent,apt-transport-https,ca-certificates,curl,gnupg,lsb-release \
        --run-command "install -m 0755 -d /etc/apt/keyrings" \
        --run-command "curl -fsSL ${DOCKER_BASE}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg" \
        --run-command "chmod a+r /etc/apt/keyrings/docker.gpg" \
        --run-command "echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_BASE} ${REPO_CODENAME} stable' > /etc/apt/sources.list.d/docker.list" \
        --run-command "apt-get update -qq" \
        --run-command "apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin" \
        --run-command "systemctl enable docker" \
        --run-command "systemctl enable qemu-guest-agent" >/dev/null

    # PATH-Fix separat
    virt-customize -q -a "${FILE}" \
        --run-command "sed -i 's#^ENV_SUPATH.*#ENV_SUPATH  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin#' /etc/login.defs || true" \
        --run-command "sed -i 's#^ENV_PATH.*#ENV_PATH    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin#' /etc/login.defs || true" \
        --run-command "printf 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' >/etc/environment" \
        --run-command "grep -q 'export PATH=' /root/.bashrc || echo 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' >> /root/.bashrc" >/dev/null

    msg_ok "Docker injected into image"
fi

# ---------- PVE9: First-boot installer inside guest ----------
if [ "$INSTALL_MODE" = "firstboot" ]; then
    msg_info "Preparing first-boot Docker installer (${CODENAME}, $(basename "$DOCKER_BASE"))"
    mkdir -p firstboot
    cat >firstboot/firstboot-docker.sh <<'EOSH'
#!/usr/bin/env bash
set -euxo pipefail

LOG=/var/log/firstboot-docker.log
exec >>"$LOG" 2>&1

mark_done() { mkdir -p /var/lib/firstboot; date > /var/lib/firstboot/docker.done; }
retry() { local t=$1; shift; local n=0; until "$@"; do n=$((n+1)); [ "$n" -ge "$t" ] && return 1; sleep 5; done; }

wait_network() {
  retry 60 getent hosts deb.debian.org || retry 60 getent hosts archive.ubuntu.com
  retry 60 bash -lc 'curl -fsS https://download.docker.com/ >/dev/null'
}

fix_path() {
  sed -i 's#^ENV_SUPATH.*#ENV_SUPATH  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin#' /etc/login.defs || true
  sed -i 's#^ENV_PATH.*#ENV_PATH    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin#' /etc/login.defs || true
  printf 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' >/etc/environment
  grep -q 'export PATH=' /root/.bashrc || echo 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' >> /root/.bashrc
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
}

main() {
  export DEBIAN_FRONTEND=noninteractive
  mkdir -p /etc/apt/apt.conf.d
  printf 'Acquire::Retries "10";\nAcquire::http::Timeout "60";\nAcquire::https::Timeout "60";\n' >/etc/apt/apt.conf.d/80-retries-timeouts

  wait_network

  . /etc/os-release
  CODENAME="${VERSION_CODENAME:-bookworm}"
  case "$ID" in
    ubuntu) DOCKER_BASE="https://download.docker.com/linux/ubuntu" ;;
    debian|*) DOCKER_BASE="https://download.docker.com/linux/debian" ;;
  esac
  REPO_CODENAME="$CODENAME"
  if [ "$ID" = "debian" ] && [ "$CODENAME" = "trixie" ]; then REPO_CODENAME="bookworm"; fi

  retry 20 apt-get update -qq
  retry 10 apt-get install -y ca-certificates curl gnupg qemu-guest-agent apt-transport-https lsb-release software-properties-common

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "${DOCKER_BASE}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_BASE} ${REPO_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

  retry 20 apt-get update -qq
  retry 10 apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  systemctl enable --now qemu-guest-agent || true
  systemctl enable --now docker

  fix_path

  command -v docker >/dev/null
  systemctl is-active --quiet docker

  mark_done
}
main
EOSH
    chmod +x firstboot/firstboot-docker.sh

    cat >firstboot/firstboot-docker.service <<'EOUNIT'
[Unit]
Description=First boot: install Docker & QGA
After=network-online.target cloud-init.service
Wants=network-online.target
ConditionPathExists=!/var/lib/firstboot/docker.done
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/firstboot-docker.sh
Restart=on-failure
RestartSec=10s
TimeoutStartSec=0
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOUNIT

    echo "$HN" >firstboot/hostname

    virt-customize -q -a "${FILE}" \
        --copy-in firstboot/firstboot-docker.sh:/usr/local/sbin \
        --copy-in firstboot/firstboot-docker.service:/etc/systemd/system \
        --copy-in firstboot/hostname:/etc \
        --run-command "chmod +x /usr/local/sbin/firstboot-docker.sh" \
        --run-command "systemctl enable firstboot-docker.service" \
        --run-command "echo -n > /etc/machine-id" \
        --run-command "truncate -s 0 /etc/hostname && mv /etc/hostname /etc/hostname.orig && echo '${HN}' >/etc/hostname" >/dev/null

    msg_ok "First-boot Docker installer injected"
fi

# ---------- Expand partition offline ----------
msg_info "Expanding root partition to use full disk space"
qemu-img create -f qcow2 expanded.qcow2 ${DISK_SIZE} >/dev/null 2>&1
virt-resize --expand /dev/sda1 ${FILE} expanded.qcow2 >/dev/null 2>&1
mv expanded.qcow2 ${FILE} >/dev/null 2>&1
msg_ok "Expanded image to full size"

# ---------- Create VM shell (q35) ----------
msg_info "Creating a Docker VM shell"
qm create "$VMID" -machine q35 -bios ovmf -agent 1 -tablet 0 -localtime 1 ${CPU_TYPE} \
    -cores "$CORE_COUNT" -memory "$RAM_SIZE" -name "$HN" -tags community-script \
    -net0 "virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU" -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null
msg_ok "Created VM shell"

# ---------- Import disk ----------
msg_info "Importing disk into storage ($STORAGE)"
if qm disk import --help >/dev/null 2>&1; then IMPORT_CMD=(qm disk import); else IMPORT_CMD=(qm importdisk); fi
IMPORT_OUT="$("${IMPORT_CMD[@]}" "$VMID" "${FILE}" "$STORAGE" --format qcow2 2>&1 || true)"
DISK_REF="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*successfully imported disk '\([^']\+\)'.*/\1/p" | tr -d "\r\"'")"
[[ -z "$DISK_REF" ]] && DISK_REF="$(pvesm list "$STORAGE" | awk -v id="$VMID" '$5 ~ ("vm-"id"-disk-") {print $1":"$5}' | sort | tail -n1)"
[[ -z "$DISK_REF" ]] && {
    msg_error "Unable to determine imported disk reference."
    echo "$IMPORT_OUT"
    exit 1
}
msg_ok "Imported disk (${CL}${BL}${DISK_REF}${CL})"

# ---------- Attach EFI + root disk ----------
msg_info "Attaching EFI and root disk"
qm set "$VMID" \
    --efidisk0 "${STORAGE}:0${FORMAT}" \
    --scsi0 "${DISK_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE}" \
    --boot order=scsi0 \
    --serial0 socket >/dev/null
qm set "$VMID" --agent enabled=1 >/dev/null
msg_ok "Attached EFI and root disk"

# ---------- Ensure final size (PVE layer) ----------
msg_info "Resizing disk to $DISK_SIZE (PVE layer)"
qm resize "$VMID" scsi0 "${DISK_SIZE}" >/dev/null || true
msg_ok "Resized disk"

# ---------- Description ----------
DESCRIPTION=$(
    cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Docker VM</h2>

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

msg_ok "Created a Docker VM ${CL}${BL}(${HN})"

if [ "$START_VM" == "yes" ]; then
    msg_info "Starting Docker VM"
    qm start $VMID
    msg_ok "Started Docker VM"
fi

post_update_to_api "done" "none"
msg_ok "Completed Successfully!\n"
