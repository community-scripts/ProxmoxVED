#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

set -eEuo pipefail

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

BL="\033[36m"
RD="\033[01;31m"
CM='\xE2\x9C\x94\033'
GN="\033[1;92m"
CL="\033[m"

header_info
echo "Loading..."
whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE LXC Updater" \
    --yesno "This Will Clean logs, cache and update apt/apk lists on selected LXC Containers. Proceed?" 10 68 || exit

NODE=$(hostname)
EXCLUDE_MENU=()
MSG_MAX_LENGTH=0
while read -r TAG ITEM; do
    OFFSET=2
    ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
    EXCLUDE_MENU+=("$TAG" "$ITEM " "OFF")
done < <(pct list | awk 'NR>1')
excluded_containers=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on $NODE" \
    --checklist "\nSelect containers to skip from cleaning:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${EXCLUDE_MENU[@]}" \
    3>&1 1>&2 2>&3 | tr -d '"') || exit

function clean_container() {
    local container=$1
    local os=$2
    header_info
    name=$(pct exec "$container" hostname)
    echo -e "${BL}[Info]${GN} Cleaning ${name} (${os}) ${CL} \n"
    if [[ "$os" == "alpine" ]]; then
        pct exec "$container" -- sh -c \
            "apk update && apk cache clean && rm -rf /var/cache/apk/*"
    else
        pct exec "$container" -- bash -c \
            "apt-get -y --purge autoremove && apt-get -y autoclean && \
       bash <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/clean.sh) && \
       rm -rf /var/lib/apt/lists/* && apt-get update"
    fi
}

for container in $(pct list | awk 'NR>1 {print $1}'); do
    if [[ " ${excluded_containers[*]} " =~ " $container " ]]; then
        header_info
        echo -e "${BL}[Info]${GN} Skipping ${BL}$container${CL}"
        sleep 1
        continue
    fi

    # locked?
    if pct status "$container" | grep -q 'locked'; then
        header_info
        echo -e "${BL}[Info]${RD} Skipping locked container ${BL}$container${CL}"
        sleep 1
        continue
    fi

    os=$(pct config "$container" | awk '/^ostype/ {print $2}')
    [[ "$os" != "debian" && "$os" != "ubuntu" && "$os" != "alpine" ]] && {
        header_info
        echo -e "${BL}[Info]${RD} Skipping unsupported OS in $container: $os ${CL}"
        sleep 1
        continue
    }

    status=$(pct status "$container" | awk '{print $2}')
    template=$(pct config "$container" | grep -q "template:" && echo "true" || echo "false")

    if [[ "$template" == "false" && "$status" == "stopped" ]]; then
        if whiptail --backtitle "Proxmox VE Helper Scripts" \
            --title "Container $container is stopped" \
            --yesno "Container $container is stopped.\n\nStart and clean?" 10 58; then
            echo -e "${BL}[Info]${GN} Starting${BL} $container ${CL} \n"
            pct start "$container"
            echo -e "${BL}[Info]${GN} Waiting for${BL} $container${CL}${GN} to start ${CL} \n"
            sleep 5
            clean_container "$container" "$os"
            echo -e "${BL}[Info]${GN} Shutting down${BL} $container ${CL} \n"
            pct shutdown "$container" &
        else
            echo -e "${BL}[Info]${GN} Skipping stopped container ${BL}$container${CL}"
        fi
    elif [[ "$status" == "running" ]]; then
        clean_container "$container" "$os"
    fi
done

wait
header_info
echo -e "${GN} Finished, selected containers cleaned. ${CL} \n"
