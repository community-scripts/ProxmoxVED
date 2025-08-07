#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

set -eEuo pipefail

function header_info() {
  clear
  cat <<"EOF"
    _______ __                     __                    ______     _
   / ____(_) /__  _______  _______/ /____  ____ ___     /_  __/____(_)___ ___
  / /_  / / / _ \/ ___/ / / / ___/ __/ _ \/ __ `__ \     / / / ___/ / __ `__ \
 / __/ / / /  __(__  ) /_/ (__  ) /_/  __/ / / / / /    / / / /  / / / / / / /
/_/   /_/_/\___/____/\__, /____/\__/\___/_/ /_/ /_/    /_/ /_/  /_/_/ /_/ /_/
                    /____/
EOF
}

BL="\033[36m"
RD="\033[01;31m"
CM='\xE2\x9C\x94\033'
GN="\033[1;92m"
CL="\033[m"

header_info
echo "Loading..."

ROOT_FS=$(df -Th "/" | awk 'NR==2 {print $2}')
if [ "$ROOT_FS" != "ext4" ]; then
  whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Warning" \
    --yesno "Root filesystem is not ext4 ($ROOT_FS).\nContinue anyway?" 10 58 || exit 1
fi

NODE=$(hostname)
EXCLUDE_MENU=()
MSG_MAX_LENGTH=0

while read -r TAG ITEM; do
  OFFSET=2
  ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=$((${#ITEM} + OFFSET))
  EXCLUDE_MENU+=("$TAG" "$ITEM " "OFF")
done < <(pct list | awk 'NR>1')

excluded_containers_raw=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
  --title "Containers on $NODE" \
  --checklist "\nSelect containers to skip from trimming:\n" \
  16 $((MSG_MAX_LENGTH + 23)) 6 "${EXCLUDE_MENU[@]}" 3>&1 1>&2 2>&3)

[ $? -ne 0 ] && exit

read -ra EXCLUDED <<<$(echo "$excluded_containers_raw" | tr -d '"')

function trim_container() {
  local container="$1"
  header_info
  echo -e "${BL}[Info]${GN} Trimming ${BL}$container${CL} \n"

  local before_trim after_trim
  before_trim=$(lvs --noheadings -o lv_name,data_percent | awk -v ctid="vm-${container}-disk-0" '$1 == ctid {gsub(/%/, "", $2); print $2}')
  echo -e "${RD}Data before trim $before_trim%${CL}"

  pct fstrim "$container"

  after_trim=$(lvs --noheadings -o lv_name,data_percent | awk -v ctid="vm-${container}-disk-0" '$1 == ctid {gsub(/%/, "", $2); print $2}')
  echo -e "${GN}Data after trim $after_trim%${CL}"

  sleep 0.5
}

for container in $(pct list | awk 'NR>1 {print $1}'); do
  if [[ " ${EXCLUDED[*]} " =~ " $container " ]]; then
    header_info
    echo -e "${BL}[Info]${GN} Skipping ${BL}$container${CL}"
    sleep 0.5
    continue
  fi
  if pct config "$container" | grep -q "template:"; then
    header_info
    echo -e "${BL}[Info]${GN} Skipping ${container} ${RD}$container is a template${CL} \n"
    sleep 0.5
    continue
  fi
  state=$(pct status "$container" | awk '{print $2}')
  if [[ "$state" != "running" ]]; then
    header_info
    echo -e "${BL}[Info]${GN} Skipping $container (not running)${CL}"
    sleep 0.5
    continue
  fi
  trim_container "$container"
done

header_info
echo -e "${GN}Finished, LXC Containers Trimmed.${CL} \n"
exit 0
