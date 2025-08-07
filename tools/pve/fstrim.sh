#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
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
GN="\033[1;92m"
CL="\033[m"

header_info
echo "Loading..."

whiptail --backtitle "Proxmox VE Helper Scripts" \
  --title "About fstrim (LXC)" \
  --msgbox "The 'fstrim' command releases unused blocks back to the storage device. This only makes sense for containers on SSD, NVMe, Thin-LVM, or storage with discard/TRIM support.\n\nIf your root filesystem or container disks are on classic HDDs, thick LVM, or unsupported storage types, running fstrim will have no effect.\n\nRecommended:\n- Use fstrim only on SSD, NVMe, or thin-provisioned storage with discard enabled.\n- For ZFS, ensure 'autotrim=on' is set on your pool.\n\nSee: https://pve.proxmox.com/wiki/Shrinking_LXC_disks" 16 88

ROOT_FS=$(df -Th "/" | awk 'NR==2 {print $2}')
if [ "$ROOT_FS" != "ext4" ]; then
  whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Warning" \
    --yesno "Root filesystem is not ext4 ($ROOT_FS).\nContinue anyway?" 12 80 || exit 1
fi

NODE=$(hostname)
MAX_NAME_LEN=0
declare -A NAMES
declare -A STATUS

for CTID in $(pct list | awk 'NR>1 {print $1}'); do
  NAME=$(pct config "$CTID" | awk -F': ' '/^hostname:/ {print $2}')
  CTSTATUS=$(pct status "$CTID" | awk '{print $2}')
  NAMES["$CTID"]="$NAME"
  STATUS["$CTID"]="$CTSTATUS"
  ((${#NAME} > MAX_NAME_LEN)) && MAX_NAME_LEN=${#NAME}
done

FMT="%-5s | %-${MAX_NAME_LEN}s | %-8s"

EXCLUDE_MENU=()
for CTID in "${!NAMES[@]}"; do
  DESC=$(printf "$FMT" "$CTID" "${NAMES[$CTID]}" "${STATUS[$CTID]}")
  EXCLUDE_MENU+=("$CTID" "$DESC" "OFF")
done

excluded_containers_raw=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
  --title "Containers on $NODE" \
  --checklist "\nSelect containers to skip from trimming:\n" \
  20 $((MAX_NAME_LEN + 40)) 12 "${EXCLUDE_MENU[@]}" 3>&1 1>&2 2>&3)
[ $? -ne 0 ] && exit

read -ra EXCLUDED <<<$(echo "$excluded_containers_raw" | tr -d '"')

STOPPED_MENU=()
for CTID in "${!NAMES[@]}"; do
  if [[ "${STATUS[$CTID]}" == "stopped" ]]; then
    DESC=$(printf "$FMT" "$CTID" "${NAMES[$CTID]}" "${STATUS[$CTID]}")
    STOPPED_MENU+=("$CTID" "$DESC" "OFF")
  fi
done

TO_START=()
if [ ${#STOPPED_MENU[@]} -gt 0 ]; then
  selected=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Stopped LXC Containers" \
    --checklist "\nSome LXC containers are currently stopped.\nWhich ones do you want to temporarily start for the trim operation?\n(They can be stopped again afterwards)\n" \
    16 $((MAX_NAME_LEN + 40)) 8 "${STOPPED_MENU[@]}" 3>&1 1>&2 2>&3)
  [ $? -ne 0 ] && exit
  read -ra TO_START <<<$(echo "$selected" | tr -d '"')
fi

declare -A WAS_STOPPED
for ct in "${TO_START[@]}"; do
  WAS_STOPPED["$ct"]=1
done

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

for CTID in $(pct list | awk 'NR>1 {print $1}'); do
  if [[ " ${EXCLUDED[*]} " =~ " $CTID " ]]; then
    header_info
    echo -e "${BL}[Info]${GN} Skipping $CTID (excluded)${CL}"
    sleep 0.5
    continue
  fi
  if pct config "$CTID" | grep -q "template:"; then
    header_info
    echo -e "${BL}[Info]${GN} Skipping $CTID (template)${CL}\n"
    sleep 0.5
    continue
  fi
  if [[ "${STATUS[$CTID]}" != "running" ]]; then
    if [[ -n "${WAS_STOPPED[$CTID]:-}" ]]; then
      header_info
      echo -e "${BL}[Info]${GN} Starting $CTID for trim...${CL}"
      pct start "$CTID"
      sleep 2
    else
      header_info
      echo -e "${BL}[Info]${GN} Skipping $CTID (not running, not selected)${CL}"
      sleep 0.5
      continue
    fi
  fi

  trim_container "$CTID"

  if [[ -n "${WAS_STOPPED[$CTID]:-}" ]]; then
    if whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "Stop container again?" \
      --yesno "Container $CTID (${NAMES[$CTID]}) was started for the trim operation.\n\nDo you want to stop it again now?" 10 60; then
      header_info
      echo -e "${BL}[Info]${GN} Stopping $CTID again...${CL}"
      pct stop "$CTID"
      sleep 1
    else
      header_info
      echo -e "${BL}[Info]${GN} Leaving $CTID running as requested.${CL}"
      sleep 1
    fi
  fi
done

header_info
echo -e "${GN}Finished, LXC Containers Trimmed.${CL} \n"
exit 0
