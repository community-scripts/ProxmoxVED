#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster) | Co-Author: remz1337
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info() {
  clear
  cat <<"EOF"
   __  __          __      __          __   _  ________   _____                 _               
  / / / /___  ____/ /___ _/ /____     / /  | |/ / ____/  / ___/___  ______   __(_)_______  _____
 / / / / __ \/ __  / __ `/ __/ _ \   / /   |   / /       \__ \/ _ \/ ___/ | / / / ___/ _ \/ ___/
/ /_/ / /_/ / /_/ / /_/ / /_/  __/  / /___/   / /___    ___/ /  __/ /   | |/ / / /__/  __(__  ) 
\____/ .___/\__,_/\__,_/\__/\___/  /_____/_/|_\____/   /____/\___/_/    |___/_/\___/\___/____/  
    /_/                                                                                         

EOF
}
set -eEuo pipefail
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
CM='\xE2\x9C\x94\033'
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
header_info
echo "Loading..."
whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE LXC Service Updater" --yesno "This Will Update LXC Services. Proceed?" 10 58
NODE=$(hostname)
EXCLUDE_MENU=()
MSG_MAX_LENGTH=0
while read -r TAG ITEM; do
  OFFSET=2
  ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
  EXCLUDE_MENU+=("$TAG" "$ITEM " "OFF")
done < <(pct list | awk 'NR>1')
excluded_containers=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on $NODE" --checklist "\nSelect containers to skip from updates:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${EXCLUDE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

function needs_reboot() {
  local container=$1
  local os=$(pct config "$container" | awk '/^ostype/ {print $2}')
  local reboot_required_file="/var/run/reboot-required.pkgs"
  if [ -f "$reboot_required_file" ]; then
    if [[ "$os" == "ubuntu" || "$os" == "debian" ]]; then
      if pct exec "$container" -- [ -s "$reboot_required_file" ]; then
        return 0
      fi
    fi
  fi
  return 1
}

function update_container_service() {
  container=$1
  header_info
  name=$(pct exec "$container" hostname)
  os=$(pct config "$container" | awk '/^ostype/ {print $2}')
  if [[ "$os" == "ubuntu" || "$os" == "debian" || "$os" == "fedora" ]]; then
    disk_info=$(pct exec "$container" df /boot | awk 'NR==2{gsub("%","",$5); printf "%s %.1fG %.1fG %.1fG", $5, $3/1024/1024, $2/1024/1024, $4/1024/1024 }')
    read -ra disk_info_array <<<"$disk_info"
    echo -e "${BL}[Info]${GN} Updating ${BL}$container${CL} : ${GN}$name${CL} - ${YW}Boot Disk: ${disk_info_array[0]}% full [${disk_info_array[1]}/${disk_info_array[2]} used, ${disk_info_array[3]} free]${CL}\n"
  else
    echo -e "${BL}[Info]${GN} Updating ${BL}$container${CL} : ${GN}$name${CL} - ${YW}[No disk info for ${os}]${CL}\n"
  fi

  #1) Detect service using the service name in the update command
  pushd $(mktemp -d) >/dev/null
  pct pull "$container" /usr/bin/update update 2>/dev/null
  service=$(cat update | sed 's|.*/ct/||g' | sed 's|\.sh).*||g')
  popd >/dev/null

  #1.1) If update script not detected, return
  if [ -z "${service}" ]; then
    echo -e "${YW}[WARN]${CL} Update script not found\n"
    return
  else
    echo "${BL}[INFO]${CL} Detected service: ${GN}${service}${CL}\n"
  fi

  #2) Extract service build/update resource requirements from config/installation file
  script=$(curl -fsSL https://raw.githubusercontent.com/remz1337/ProxmoxVE/remz/ct/${service}.sh)
  config=$(pct config "$container")
  build_cpu=$(echo "$script" | { grep -m 1 "var_cpu" || test $? = 1; } | sed 's|.*=||g' | sed 's|"||g' | sed 's|.*var_cpu:-||g' | sed 's|}||g')
  build_ram=$(echo "$script" | { grep -m 1 "var_ram" || test $? = 1; } | sed 's|.*=||g' | sed 's|"||g' | sed 's|.*var_ram:-||g' | sed 's|}||g')
  run_cpu=$(echo "$script" | { grep -m 1 "pct set \$CTID -cores" || test $? = 1; } | sed 's|.*cores ||g')
  run_ram=$(echo "$script" | { grep -m 1 "pct set \$CTID -memory" || test $? = 1; } | sed 's|.*memory ||g')
  current_cpu=$(echo "$config" | grep -m 1 "cores:" | sed 's|cores: ||g')
  current_ram=$(echo "$config" | grep -m 1 "memory:" | sed 's|memory: ||g')

  #Test if all values are valid (>0)
  if [ -z "${run_cpu}" ] || [ "$run_cpu" -le 0 ]; then
    #echo "No valid value found for run_cpu. Assuming same as current configuration."
    run_cpu=$current_cpu
  fi

  if [ -z "${run_ram}" ] || [ "$run_ram" -le 0 ]; then
    #echo "No valid value found for run_ram. Assuming same as current configuration."
    run_ram=$current_ram
  fi

  if [ -z "${build_cpu}" ] || [ "$build_cpu" -le 0 ]; then
    #echo "No valid value found for build_cpu. Assuming same as current configuration."
    build_cpu=$current_cpu
  fi

  if [ -z "${build_ram}" ] || [ "$build_ram" -le 0 ]; then
    #echo "No valid value found for build_ram. Assuming same as current configuration."
    build_ram=$current_ram
  fi

  UPDATE_BUILD_RESOURCES=0
  if [ "$build_cpu" -gt "$run_cpu" ] || [ "$build_ram" -gt "$run_ram" ]; then
    UPDATE_BUILD_RESOURCES=1
  fi

  #3) if build resources are different than run resources, then:
  if [ "$UPDATE_BUILD_RESOURCES" -eq "1" ]; then
    #pct shutdown "$container"
    #sleep 2
    pct set "$container" --cores "$build_cpu" --memory "$build_ram"
    pct restart "$container"
    sleep 2
  fi

  #4) Update service, using the update command
  UPDATE_CMD="export PHS_SILENT=1;update;"
  case "$os" in
  alpine) pct exec "$container" -- ash -c "$UPDATE_CMD" ;;
  archlinux) pct exec "$container" -- bash -c "$UPDATE_CMD" ;;
  fedora | rocky | centos | alma) pct exec "$container" -- bash -c "$UPDATE_CMD" ;;
  ubuntu | debian | devuan) pct exec "$container" -- bash -c "$UPDATE_CMD" ;;
  opensuse) pct exec "$container" -- bash -c "$UPDATE_CMD" ;;
  esac

  #5) if build resources are different than run resources, then:
  if [ "$UPDATE_BUILD_RESOURCES" -eq "1" ]; then
    #pct shutdown "$container"
    #sleep 2
    pct set "$container" --cores "$run_cpu" --memory "$run_ram"
    #pct restart "$container"
    #sleep 2
  fi
}

containers_needing_reboot=()
header_info
for container in $(pct list | awk '{if(NR>1) print $1}'); do
  if [[ " ${excluded_containers[@]} " =~ " $container " ]]; then
    header_info
    echo -e "${BL}[Info]${GN} Skipping ${BL}$container${CL}"
    sleep 1
  else
    status=$(pct status $container)
    template=$(pct config $container | grep -q "template:" && echo "true" || echo "false")
    if [ "$template" == "false" ] && [ "$status" == "status: stopped" ]; then
      echo -e "${BL}[Info]${GN} Starting${BL} $container ${CL} \n"
      pct start $container
      echo -e "${BL}[Info]${GN} Waiting For${BL} $container${CL}${GN} To Start ${CL} \n"
      sleep 5
      #update_container $container
      update_container_service $container
      echo -e "${BL}[Info]${GN} Shutting down${BL} $container ${CL} \n"
      pct shutdown $container &
    elif [ "$status" == "status: running" ]; then
      #update_container $container
      update_container_service $container
    fi
    if pct exec "$container" -- [ -e "/var/run/reboot-required" ]; then
      # Get the container's hostname and add it to the list
      container_hostname=$(pct exec "$container" hostname)
      containers_needing_reboot+=("$container ($container_hostname)")
    fi
  fi
done
wait
header_info
echo -e "${GN}The process is complete, and the containers have been successfully updated.${CL}\n"
if [ "${#containers_needing_reboot[@]}" -gt 0 ]; then
  echo -e "${RD}The following containers require a reboot:${CL}"
  for container_name in "${containers_needing_reboot[@]}"; do
    echo "$container_name"
  done
fi
echo ""
