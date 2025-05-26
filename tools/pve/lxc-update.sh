#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: BvdBerg01
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info {
  clear
  cat <<"EOF"
    __   _  ________   __  __          __      __     
   / /  | |/ / ____/  / / / /___  ____/ /___ _/ /____ 
  / /   |   / /      / / / / __ \/ __  / __ `/ __/ _ \
 / /___/   / /___   / /_/ / /_/ / /_/ / /_/ / /_/  __/
/_____/_/|_\____/   \____/ .___/\__,_/\__,_/\__/\___/ 
                        /_/                           
EOF
}

  # Colors
  YW=$(echo "\033[33m")
  YWB=$(echo "\033[93m")
  BL=$(echo "\033[36m")
  RD=$(echo "\033[01;31m")
  BGN=$(echo "\033[4;92m")
  GN=$(echo "\033[1;92m")
  DGN=$(echo "\033[32m")

  # Formatting
  CL=$(echo "\033[m")
  UL=$(echo "\033[4m")
  BOLD=$(echo "\033[1m")
  BFR="\\r\\033[K"
  HOLD=" "
  TAB="  "

  # Icons
  CM="${TAB}✔️${TAB}${CL}"
  CROSS="${TAB}✖️${TAB}${CL}"
  INFO="${TAB}💡${TAB}${CL}"
  OS="${TAB}🖥️${TAB}${CL}"
  OSVERSION="${TAB}🌟${TAB}${CL}"
  CONTAINERTYPE="${TAB}📦${TAB}${CL}"
  DISKSIZE="${TAB}💾${TAB}${CL}"
  CPUCORE="${TAB}🧠${TAB}${CL}"
  RAMSIZE="${TAB}🛠️${TAB}${CL}"
  SEARCH="${TAB}🔍${TAB}${CL}"
  VERIFYPW="${TAB}🔐${TAB}${CL}"
  CONTAINERID="${TAB}🆔${TAB}${CL}"
  HOSTNAME="${TAB}🏠${TAB}${CL}"
  BRIDGE="${TAB}🌉${TAB}${CL}"
  NETWORK="${TAB}📡${TAB}${CL}"
  GATEWAY="${TAB}🌐${TAB}${CL}"
  DISABLEIPV6="${TAB}🚫${TAB}${CL}"
  DEFAULT="${TAB}⚙️${TAB}${CL}"
  MACADDRESS="${TAB}🔗${TAB}${CL}"
  VLANTAG="${TAB}🏷️${TAB}${CL}"
  ROOTSSH="${TAB}🔑${TAB}${CL}"
  CREATING="${TAB}🚀${TAB}${CL}"
  ADVANCED="${TAB}🧩${TAB}${CL}"

# This function displays an informational message with logging support.
start_spinner() {
  local msg="$1"
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spin_i=0
  local interval=0.1
  local term_width=$(tput cols)

  {
    while [ "${SPINNER_ACTIVE:-1}" -eq 1 ]; do
      printf "\r\e[2K${frames[spin_i]} ${YW}%b${CL}" "$msg" >&2
      spin_i=$(((spin_i + 1) % ${#frames[@]}))
      sleep "$interval"
    done
  } &

  SPINNER_PID=$!
}

msg_info() {
  local msg="$1"
  if [ "${SPINNER_ACTIVE:-0}" -eq 1 ]; then
    return
  fi

  SPINNER_ACTIVE=1
  start_spinner "$msg"
}

msg_ok() {
  if [ -n "${SPINNER_PID:-}" ] && ps -p "$SPINNER_PID" >/dev/null 2>&1; then
    kill "$SPINNER_PID" >/dev/null 2>&1
    wait "$SPINNER_PID" 2>/dev/null || true
  fi

  local msg="$1"
  printf "\r\e[2K${CM}${GN}%b${CL}\n" "$msg" >&2
  unset SPINNER_PID
  SPINNER_ACTIVE=0
}

msg_error() {
  if [ -n "${SPINNER_PID:-}" ] && ps -p "$SPINNER_PID" >/dev/null 2>&1; then
    kill "$SPINNER_PID" >/dev/null 2>&1
    wait "$SPINNER_PID" 2>/dev/null || true
  fi

  local msg="$1"
  printf "\r\e[2K${CROSS}${RD}%b${CL}\n" "$msg" >&2
  unset SPINNER_PID
  SPINNER_ACTIVE=0
}

header_info
echo "Loading..."
whiptail --backtitle "Proxmox VE Helper Scripts" --title "LXC Container Update" --yesno "This will update LXC container. Proceed?" 10 58 || exit

NODE=$(hostname)
containers=$(pct list | tail -n +2 | awk '{print $0 " " $4}')

if [ -z "$containers" ]; then
    whiptail --title "LXC Container Update" --msgbox "No LXC containers available!" 10 60
    exit 1
fi

menu_items=()
FORMAT="%-10s %-15s %-10s"

while read -r container; do
    container_id=$(echo $container | awk '{print $1}')
    container_name=$(echo $container | awk '{print $2}')
    container_status=$(echo $container | awk '{print $3}')
    formatted_line=$(printf "$FORMAT" "$container_name" "$container_status")
    IS_HELPERSCRIPT_LXC=$(pct exec $container_id -- [ -e /usr/bin/update ] && echo true || echo false)
    if [ "$IS_HELPERSCRIPT_LXC" = true ]; then
      menu_items+=("$container_id" "$formatted_line" "OFF")
    fi
done <<< "$containers"

CHOICE=$(whiptail --title "LXC Container Update" \
                   --radiolist "Select LXC container to update:" 25 60 13 \
                   "${menu_items[@]}" 3>&2 2>&1 1>&3)

if [ -z "$CHOICE" ]; then
    whiptail --title "LXC Container Update" \
             --msgbox "No containers selected!" 10 60
    exit 1
fi

header_info
if(whiptail --backtitle "Proxmox VE Helper Scripts" --title "LXC Container Update" --yesno "Do you want to create a backup from your container?" 10 58); then
  
  STORAGES=$(awk '/^(\S+):/ {storage=$2} /content.*backup/ {print storage}' /etc/pve/storage.cfg)

  if [ -z "$STORAGES" ]; then
    whiptail --msgbox "Geen opslag met 'backup' gevonden!" 8 40
    exit 1
  fi

  MENU_ITEMS=()
  for STORAGE in $STORAGES; do
      MENU_ITEMS+=("$STORAGE" "")
  done

  STORAGE_CHOICE=$(whiptail --title "Select storage device" --menu "Select a storage device (Only storage devices with 'backup' support are listed):" 15 50 5 "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3)

  if [ -z "$STORAGE_CHOICE" ]; then
      msg_error "No storage selected!"
      exit 1
  fi

  msg_info "Creating backup"
  vzdump $CHOICE --compress zstd --storage $STORAGE_CHOICE -notes-template "community-scripts backup updater" > /dev/null 2>&1
  status=$?

  if [ $status -eq 0 ]; then
  msg_ok "Backup created"
  pct exec $CHOICE -- update --from-pve
  exit_code=$?
  else
  msg_error "Backup failed"
  fi

else
  pct exec $CHOICE -- update --from-pve
  exit_code=$?
fi

if [ $exit_code -eq 0 ]; then
  msg_ok "Update completed"
else
  msg_info "Restoring LXC from backup"
  pct stop $CHOICE
  LXC_STORAGE=$(pct config $CHOICE | awk -F '[:,]' '/rootfs/ {print $2}')
  pct restore $CHOICE /var/lib/vz/dump/vzdump-lxc-$CHOICE-*.tar.zst --storage $LXC_STORAGE --force > /dev/null 2>&1
  pct start $CHOICE
  restorestatus=$?
  if [ $restorestatus -eq 0 ]; then
  msg_ok "Restored LXC from backup"
  else
  msg_error "Restored LXC from backup failed"
  fi
  
fi