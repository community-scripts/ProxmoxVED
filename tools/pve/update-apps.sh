#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: BvdBerg01 | Co-Author: remz1337
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/core.func)

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
                   --checklist "Select LXC containers to update:" 25 60 13 \
                   "${menu_items[@]}" 3>&2 2>&1 1>&3 | tr -d '"')

if [ -z "$CHOICE" ]; then
    whiptail --title "LXC Container Update" \
             --msgbox "No containers selected!" 10 60
    exit 1
fi

header_info
BACKUP_CHOICE="no"
if(whiptail --backtitle "Proxmox VE Helper Scripts" --title "LXC Container Update" --yesno "Do you want to backup your containers before update?" 10 58); then
  BACKUP_CHOICE="yes"
fi

UNATTENDED_UPDATE="no"
if(whiptail --backtitle "Proxmox VE Helper Scripts" --title "LXC Container Update" --yesno "Run updates unattended?" 10 58); then
  UNATTENDED_UPDATE="yes"
fi

if [ "$BACKUP_CHOICE" == "yes" ]; then
  STORAGES=$(awk '/^(\S+):/ {storage=$2} /content.*backup/ {print storage}' /etc/pve/storage.cfg)

  if [ -z "$STORAGES" ]; then
    whiptail --msgbox "No storage with 'backup' found!" 8 40
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
fi

function backup_container(){
  msg_info "Creating backup for container $1"
  vzdump $1 --compress zstd --storage $STORAGE_CHOICE -notes-template "community-scripts backup updater" > /dev/null 2>&1
  status=$?

  if [ $status -eq 0 ]; then
    msg_ok "Backup created"
  else
    msg_error "Backup failed for container $1"
    exit 1
  fi
}

UPDATE_CMD="update;"
if [ "$UNATTENDED_UPDATE" == "yes" ];then
  UPDATE_CMD="export PHS_SILENT=1;update;"
fi

for container in $CHOICE; do
  echo "Updating container:$container"

  if [ "BACKUP_CHOICE" == "yes" ];then
    backup_container $container
  fi

  #CHECK FOR RESOURCES

  #pct exec $container -- update
  pct exec "$container" -- "$UPDATE_CMD"
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    msg_ok "Update completed"
  elif [ "BACKUP_CHOICE" == "yes" ];then
    msg_info "Restoring LXC from backup"
    pct stop $container
    LXC_STORAGE=$(pct config $container | awk -F '[:,]' '/rootfs/ {print $2}')
    pct restore $container /var/lib/vz/dump/vzdump-lxc-${container}-*.tar.zst --storage $LXC_STORAGE --force > /dev/null 2>&1
    pct start $container
    restorestatus=$?
    if [ $restorestatus -eq 0 ]; then
      msg_ok "Restored LXC from backup"
    else
      msg_error "Restored LXC from backup failed"
      exit 1
    fi
  else
    msg_error "Update failed for container $container. Exiting"
    exit 1
  fi
done
