#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info() {
  clear
  cat <<"EOF"
   ________                    __   _  ________
  / ____/ /__  ____ _____     / /  | |/ / ____/
 / /   / / _ \/ __ `/ __ \   / /   |   / /
/ /___/ /  __/ /_/ / / / /  / /___/   / /___
\____/_/\___/\__,_/_/ /_/  /_____/_/|_\____/
EOF
}

set -eEuo pipefail
BL="\033[36m"
RD="\033[01;31m"
CM='\xE2\x9C\x94\033'
GN="\033[1;92m"
CL="\033[m"

header_info
echo "Loading..."

whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE LXC Updater" --yesno "This Will Clean logs, cache and update apt lists on selected LXC Containers. Proceed?" 10 58

NODE=$(hostname)
EXCLUDE_MENU=()
MSG_MAX_LENGTH=0

while read -r TAG ITEM; do
  OFFSET=2
  ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
  EXCLUDE_MENU+=("$TAG" "$ITEM " "OFF")
done < <(pct list | awk 'NR>1')

excluded_containers=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on $NODE" --checklist "\nSelect containers to skip from cleaning:\n" \
  16 $((MSG_MAX_LENGTH + 23)) 6 "${EXCLUDE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

if [ $? -ne 0 ]; then
  exit
fi

function run_lxc_clean() {
  local container=$1
  header_info
  name=$(pct exec "$container" hostname)
  echo -e "${BL}[Info]${GN} Cleaning ${name} ${CL} \n"

  pct exec "$container" -- bash -c '
    BL="\033[36m"
    GN="\033[1;92m"
    CL="\033[m"
    name=$(hostname)
    echo -e "${BL}[Info]${GN} Cleaning $name${CL} \n"

    cache=$(find /var/cache/ -type f 2>/dev/null)
    if [[ -z "$cache" ]]; then
      echo -e "No cache files found. \n"
      sleep 1
    else
      find /var/cache -type f -delete 2>/dev/null
      echo "Cache removed."
      sleep 1
    fi

    echo -e "${BL}[Info]${GN} Cleaning $name${CL} \n"
    logs=$(find /var/log/ -type f 2>/dev/null)
    if [[ -z "$logs" ]]; then
      echo -e "No log files found. \n"
      sleep 1
    else
      find /var/log -type f -delete 2>/dev/null
      echo "Logs removed."
      sleep 1
    fi

    echo -e "${BL}[Info]${GN} Cleaning $name${CL} \n"
    echo -e "${GN}Populating apt lists${CL} \n"
    apt-get -y --purge autoremove
    apt-get -y autoclean
    rm -rf /var/lib/apt/lists/*
    apt-get update
  '
}

for container in $(pct list | awk '{if(NR>1) print $1}'); do
  if [[ " ${excluded_containers[@]} " =~ " $container " ]]; then
    header_info
    echo -e "${BL}[Info]${GN} Skipping ${BL}$container${CL}"
    sleep 1
    continue
  fi

  os=$(pct config "$container" | awk '/^ostype/ {print $2}')
  if [ "$os" != "debian" ] && [ "$os" != "ubuntu" ]; then
    header_info
    echo -e "${BL}[Info]${GN} Skipping ${RD}$container is not Debian or Ubuntu${CL} \n"
    sleep 1
    continue
  fi

  status=$(pct status "$container")
  template=$(pct config "$container" | grep -q "template:" && echo "true" || echo "false")

  if [ "$template" == "false" ] && [ "$status" == "status: stopped" ]; then
    echo -e "${BL}[Info]${GN} Starting${BL} $container ${CL} \n"
    pct start "$container"
    echo -e "${BL}[Info]${GN} Waiting For${BL} $container${CL}${GN} To Start ${CL} \n"
    sleep 5
    run_lxc_clean "$container"
    echo -e "${BL}[Info]${GN} Shutting down${BL} $container ${CL} \n"
    pct shutdown "$container" &
  elif [ "$status" == "status: running" ]; then
    run_lxc_clean "$container"
  fi
done

wait
header_info
echo -e "${GN} Finished, Selected Containers Cleaned. ${CL} \n"
