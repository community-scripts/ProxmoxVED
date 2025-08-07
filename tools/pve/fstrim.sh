#!/usr/bin/env bash

set -eEuo pipefail

function header_info() {
  clear
  cat <<"EOF"
    _______ __                     __                    ______     _
   / ____(_) /__  _______  _______/ /____  ____ ___     /_  __/____(_)___ ___
  / /_  / / / _ \/ ___/ / / / ___/ __/ _ \/ __ `__ \     / / / ___/ / / / / / /
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
EXCLUDE_MENU=()
STOPPED_MENU=()
MAX_NAME_LEN=0
MAX_STAT_LEN=0

# Build arrays with one pct list
mapfile -t CTLINES < <(pct list | awk 'NR>1')

for LINE in "${CTLINES[@]}"; do
  CTID=$(awk '{print $1}' <<<"$LINE")
  STATUS=$(awk '{print $2}' <<<"$LINE")
  NAME=$(awk '{print $3}' <<<"$LINE")
  ((${#NAME} > MAX_NAME_LEN)) && MAX_NAME_LEN=${#NAME}
  ((${#STATUS} > MAX_STAT_LEN)) && MAX_STAT_LEN=${#STATUS}
done

FMT="%-5s | %-${MAX_NAME_LEN}s | %-${MAX_STAT_LEN}s"

for LINE in "${CTLINES[@]}"; do
  CTID=$(awk '{print $1}' <<<"$LINE")
  STATUS=$(awk '{print $2}' <<<"$LINE")
  NAME=$(awk '{print $3}' <<<"$LINE")
  DESC=$(printf "$FMT" "$CTID" "$NAME" "$STATUS")
  EXCLUDE_MENU+=("$CTID" "$DESC" "OFF")
  if [[ "$STATUS" == "stopped" ]]; then
    STOPPED_MENU+=("$CTID" "$DESC" "OFF")
  fi
done

excluded_containers_raw=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
  --title "Containers on $NODE" \
  --checklist "\nSelect containers to skip from trimming:\n" \
  20 $((MAX_NAME_LEN + MAX_STAT_LEN + 20)) 12 "${EXCLUDE_MENU[@]}" 3>&1 1>&2 2>&3)
[ $? -ne 0 ] && exit
read -ra EXCLUDED <<<$(echo "$excluded_containers_raw" | tr -d '"')

TO_START=()
if [ ${#STOPPED_MENU[@]} -gt 0 ]; then
  echo ""
  echo "Some containers are currently stopped."
  for ((i = 0; i < ${#STOPPED_MENU[@]}; i += 3)); do
    CTID="${STOPPED_MENU[i]}"
    DESC="${STOPPED_MENU[i + 1]}"
    read -rp "Temporarily start CT $DESC for fstrim? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      TO_START+=("$CTID")
    fi
  done
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

for LINE in "${CTLINES[@]}"; do
  CTID=$(awk '{print $1}' <<<"$LINE")
  STATUS=$(awk '{print $2}' <<<"$LINE")
  NAME=$(awk '{print $3}' <<<"$LINE")
  if [[ " ${EXCLUDED[*]} " =~ " $CTID " ]]; then
    header_info
    echo -e "${BL}[Info]${GN} Skipping $CTID ($NAME, excluded)${CL}"
    sleep 0.5
    continue
  fi
  if pct config "$CTID" | grep -q "template:"; then
    header_info
    echo -e "${BL}[Info]${GN} Skipping $CTID ($NAME, template)${CL}\n"
    sleep 0.5
    continue
  fi
  if [[ "$STATUS" != "running" ]]; then
    if [[ -n "${WAS_STOPPED[$CTID]:-}" ]]; then
      header_info
      echo -e "${BL}[Info]${GN} Starting $CTID ($NAME) for trim...${CL}"
      pct start "$CTID"
      sleep 2
    else
      header_info
      echo -e "${BL}[Info]${GN} Skipping $CTID ($NAME, not running, not selected)${CL}"
      sleep 0.5
      continue
    fi
  fi

  trim_container "$CTID"

  if [[ -n "${WAS_STOPPED[$CTID]:-}" ]]; then
    read -rp "Stop CT $CTID ($NAME) again after trim? [Y/n]: " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
      header_info
      echo -e "${BL}[Info]${GN} Stopping $CTID ($NAME) again...${CL}"
      pct stop "$CTID"
      sleep 1
    else
      header_info
      echo -e "${BL}[Info]${GN} Leaving $CTID ($NAME) running as requested.${CL}"
      sleep 1
    fi
  fi
done

header_info
echo -e "${GN}Finished, LXC Containers Trimmed.${CL} \n"
exit 0
