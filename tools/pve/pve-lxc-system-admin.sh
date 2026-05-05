#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info() {
  clear
  cat <<"EOF"
    ____ _    ________   __   _  ________   _____            __                    ___       __          _     
   / __ \ |  / / ____/  / /  | |/ / ____/  / ___/__  _______/ /____  ____ ___     /   | ____/ /___ ___  (_)___ 
  / /_/ / | / / __/    / /   |   / /       \__ \/ / / / ___/ __/ _ \/ __ `__ \   / /| |/ __  / __ `__ \/ / __ \
 / ____/| |/ / /___   / /___/   / /___    ___/ / /_/ (__  ) /_/  __/ / / / / /  / ___ / /_/ / / / / / / / / / /
/_/     |___/_____/  /_____/_/|_\____/   /____/\__, /____/\__/\___/_/ /_/ /_/  /_/  |_\__,_/_/ /_/ /_/_/_/ /_/ 
                                              /____/                                                           

EOF
}

function whiptail_menu() {
  MENU_ARRAY=()
  MSG_MAX_LENGTH=0
  while read -r TAG ITEM; do
    OFFSET=2
    ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
    MENU_ARRAY+=("$TAG" "$ITEM " "OFF")
  done < <(echo "$1")
}

function restart_container_service() {
  local service=$1
  local container=$2
  local name=$3
  if pct exec "${container}" -- bash -c "systemctl is-enabled ${service} >/dev/null 2>&1"; then
    echo -e "\n${BL}[Info]${GN} Restarting ${service} inside${BL} ${name}${GN} with output: ${CL}\n"
    pct exec "${container}" -- bash -c "systemctl restart ${service} && systemctl status ${service}" 2>&1
  fi
}

function get_user_home() {
  local user=$1
  local container=$2
  local command_1="grep ${user} /etc/passwd | awk -F ':' '{print \$6}'"
  if [ "${container}" ]; then
    pct exec "${container}" -- bash -c "${command_1}" 2>&1
  else
    eval "${command_1}"
  fi
}

function set_permissions() {
  local user=$1
  local user_home=$2
  local container=$3
  local command_1="mkdir -p ${user_home}/.ssh && chown -R ${user} ${user_home} && chgrp -R ${user} ${user_home} && chmod 700 ${user_home}/.ssh && chmod -f 600 ${user_home}/.ssh/* ; true"
  if [ "${container}" ]; then
    pct exec "${container}" -- bash -c "${command_1}" 2>&1
  else
    eval "${command_1}"
  fi
}

function delete_user() {
  local user=$1
  local container=$2
  local user_home
  user_home=$(get_user_home "${user}" "${container}")
  local command_1="userdel ${user} && rm -R ${user_home}"
  if [ "${container}" ]; then
    local name
    name=$(pct exec "${container}" hostname)
    if [ "${user}" ] && [ "${user_home}" ]; then
      echo -e "${BL}[Info]${GN} Delete User ${user} inside${BL} ${name}${GN} ${CL}$(pct exec "${container}" -- bash -c "${command_1}" 2>&1)"
    else
      echo -e "${BL}[Info]${GN} User ${user} not exists inside${BL} ${name}${GN}: ${CL} Skipping"
    fi
  else
    eval "${command_1}"
  fi
}

function copy_authorized_keys() {
  local user=$1
  local container=$2
  local name=$3
  local user_home
  user_home=$(get_user_home "${user}" "${container}")
  local command_1="ls -l ${user_home}/.ssh/authorized_keys"
  local command_2="cat /etc/ssh/sshd_config | grep \"^PubkeyAuthentication yes\""
  local command_3="sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config"
  local command_4="cat /etc/ssh/sshd_config | grep PubkeyAuthentication"
  if pct push "${container}" "${user_home}"/.ssh/authorized_keys "${user_home}"/.ssh/authorized_keys >/dev/null 2>&1; then
    set_permissions "${user}" "${user_home}" "${container}"
    echo -e "${BL}[Info]${GN} Copy authorized_keys inside${BL} ${name}${GN}: ${CL}$(pct exec "${container}" -- bash -c "${command_1}" 2>&1)"
    if ! pct exec "${container}" -- bash -c "${command_2}" >/dev/null 2>&1; then
      pct exec "${container}" -- bash -c "${command_3}" 2>&1
      echo -e "${BL}[Info]${GN} Copy ${user}'s authorized_keys inside${BL} ${name}${GN} ${CL}"
      restart_container_service "ssh.service" "${container}" "${name}"
      echo -e ""
    fi
    echo -e "${BL}[Info]${GN} sshd configuration inside${BL} ${name}${GN}: ${CL}$(pct exec "${container}" -- bash -c "${command_4}" 2>&1)"
  else
    echo -e "${BL}[ERROR]${GN} Copy authorized_keys inside${BL} ${name}${GN}: ${RD}Unexpected error for user ${user}${CL}"
  fi
}

function maintain_container_user() {
  local user=$1
  local user_comment=$2
  local container=$3
  local name
  name=$(pct exec "${container}" hostname)
  local command_1="groups ${user}"
  local command_2="useradd -G 100 -m -s /bin/bash -c \"${user_comment}\" ${user} && usermod -aG sudo ${user}"
  local command_3="cat /etc/sudoers | grep '%sudo	ALL=(ALL:ALL) NOPASSWD:ALL'"
  local command_4="sed -i 's/%sudo	ALL=(ALL:ALL) ALL/%sudo	ALL=(ALL:ALL) NOPASSWD:ALL/g' /etc/sudoers"
  if pct exec "${container}" -- bash -c "${command_1} >/dev/null 2>&1"; then
    echo -e "${BL}[Info]${GN} User with group memberships already exists inside${BL} ${name}${GN}: ${CL}$(pct exec "${container}" -- bash -c "${command_1}" 2>&1)"
  else
    pct exec "${container}" -- bash -c "${command_2}" 2>&1
    local user_home
    user_home=$(get_user_home "${user}" "${container}")
    set_permissions "${user}" "${user_home}" "${container}"
    echo -e "${BL}[Info]${GN} Add user with group memberships inside${BL} ${name}${GN}: ${CL}$(pct exec "${container}" -- bash -c "${command_1}" 2>&1)"
  fi
  if ! pct exec "${container}" -- bash -c "${command_3} >/dev/null 2>&1"; then
    pct exec "${container}" -- bash -c "${command_4}" 2>&1
  fi
  echo -e "${BL}[Info]${GN} sudoers configuration inside${BL} ${name}${GN}: ${CL}$(pct exec "${container}" -- bash -c "${command_3}" 2>&1)"
  copy_authorized_keys "${user}" "${container}" "${name}"
}

function add_node_user() {
  USER_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE LXC System Admin" --inputbox "User Name?" 10 58 3>&1 1>&2 2>&3)
  USER_COMMENT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE LXC System Admin" --inputbox "User Comment for User '${USER_NAME}'?" 10 58 3>&1 1>&2 2>&3)
  useradd -G 100 -m -s /bin/bash -c "${USER_COMMENT}" "${USER_NAME}" && usermod -aG sudo "${USER_NAME}"
  keygen_node_user "${USER_NAME}" "New Key"
}

function keygen_node_user() {
  local user=$1
  local user_domain
  user_domain=$(hostname -d)
  local user_home
  user_home=$(get_user_home "${user}" "")
  local private_key="${user_home}/.ssh/id_ed25519_${user}"
  mkdir -p "${user_home}"/.ssh
  rm -f "${private_key}"*
  echo -e "${BL}[Info]${GN} Create/Renew Private Key for user '${user}':${CL}\n"
  ssh-keygen -q -t ed25519 -C "${user}@${user_domain}" -f "${private_key}"
  cp "${private_key}".pub "${user_home}"/.ssh/authorized_keys
  set_permissions "${user}" "${user_home}" ""
  sed -i 's/%sudo	ALL=(ALL:ALL) ALL/%sudo	ALL=(ALL:ALL) NOPASSWD:ALL/g' /etc/sudoers
  sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
  echo -e ""
}

function show_private_key() {
  local user=$1
  local user_home
  user_home=$(get_user_home "${user}" "")
  echo -e "Private Key of User '${user}':\n"
  cat "${user_home}"/.ssh/id_ed25519_"${user}"
  echo -e ""
  exit
}

function authorization() {
  local user=$1
  local action=$2
  local user_home
  user_home=$(get_user_home "${user}" "")
  local private_key=".ssh/id_ed25519_${user}"
  local id_file="IdentityFile ~/${private_key}"

  whiptail_menu "$(awk -F ':' '$3 == 0 || $3>=1000 && $7 == "/bin/bash" && NR>1 {print $1 " " $2 ":" $3 ":" $4 ":" $5 ":" $6 ":" $7}' /etc/passwd)"
  local user_lxc
  user_lxc=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Users on ${NODE}" --radiolist "\nSelect a User to ${action} SSH access with Private Key of User '${user}':\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${MENU_ARRAY[@]}" 3>&1 1>&2 2>&3 | tr -d '"')
  [[ -z ${user_lxc} ]] && echo -e "${BL}[ERROR]${GN} ${RD}No User selected!${CL}\n" && exit

  whiptail_menu "$(pct list | awk 'NR>1')"
  local container
  container=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on ${NODE}" --radiolist "\nSelect Container whose local User '${user_lxc}' to ${action} SSH access using the Private Key of User '${user}':\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${MENU_ARRAY[@]}" 3>&1 1>&2 2>&3 | tr -d '"')
  [[ -z ${container} ]] && echo -e "${BL}[ERROR]${GN} ${RD}No Container selected!${CL}\n" && exit

  local name
  name=$(pct exec "${container}" hostname)
  local user_lxc_home
  user_lxc_home=$(get_user_home "${user_lxc}" "${container}")

  # both
  local command_1="grep '${id_file}' ${user_lxc_home}/.ssh/config"
  # add
  local command_2="echo '${id_file}' >> ${user_lxc_home}/.ssh/config"
  local command_3="ls -l ${user_lxc_home}/${private_key}"
  # remove
  local command_4="mv ${user_lxc_home}/.ssh/config ${user_lxc_home}/.ssh/config.bak"
  local command_5="grep -v '${id_file}' ${user_lxc_home}/.ssh/config.bak > ${user_lxc_home}/.ssh/config ; true"
  local command_6="rm -f ${user_lxc_home}/.ssh/id_ed25519_${user}"
  # both
  local command_7="ls -l ${user_lxc_home}/.ssh"
  local command_8="cat ${user_lxc_home}/.ssh/config"

  if [ "${action}" == "add" ]; then
    if ! pct push "${container}" "${user_home}"/"${private_key}" "${user_lxc_home}"/"${private_key}" >/dev/null 2>&1; then
      echo -e "\n${BL}[ERROR]${GN} Copy ${private_key} inside${BL} ${name}${GN}: ${RD}Unexpected error for user ${user_lxc}${CL}" && exit
    fi
    if ! pct exec "${container}" -- bash -c "${command_1}" >/dev/null 2>&1; then
      pct exec "${container}" -- bash -c "${command_2}" 2>&1
    fi
    set_permissions "${user_lxc}" "${user_lxc_home}" "${container}"
    echo -e "${BL}[Info]${GN} Copy Private Key of user '${user}' inside${BL} ${name}${GN}: ${CL}$(pct exec "${container}" -- bash -c "${command_3}" 2>&1)"
  else
    ! [[ -f ${user_home}/${private_key} ]] && echo -e "${BL}[ERROR]${GN} ${RD}No Private Key found!${CL}\n" && exit
    if pct exec "${container}" -- bash -c "${command_1}" >/dev/null 2>&1; then
      pct exec "${container}" -- bash -c "${command_4}" 2>&1
      pct exec "${container}" -- bash -c "${command_5}" 2>&1
      set_permissions "${user_lxc}" "${user_lxc_home}" "${container}"
    fi
    echo -e "${BL}[Info]${GN} Delete Private Key of user '${user}' inside${BL} ${name}${GN}: ${CL}$(pct exec "${container}" -- bash -c "${command_6}" 2>&1)"
  fi
  echo -e "${BL}[Info]${GN} ssh configuration of User '${user_lxc}' inside${BL} ${name}${GN}: ${CL}"
  echo
  pct exec "${container}" -- bash -c "${command_7}" 2>&1
  echo
  pct exec "${container}" -- bash -c "${command_8}" 2>&1
  echo -e "\n${GN}The process of ${USER_OPTION} is complete, and the container has been successfully modified.${CL}\n" && exit
}

set -eEuo pipefail
# shellcheck disable=SC2034
# shellcheck disable=SC2116
# shellcheck disable=SC2028
YW=$(echo "\033[33m")
# shellcheck disable=SC2116
# shellcheck disable=SC2028
BL=$(echo "\033[36m")
# shellcheck disable=SC2116
# shellcheck disable=SC2028
RD=$(echo "\033[01;31m")
# shellcheck disable=SC2034
CM='\xE2\x9C\x94\033'
# shellcheck disable=SC2116
# shellcheck disable=SC2028
GN=$(echo "\033[1;92m")
# shellcheck disable=SC2116
# shellcheck disable=SC2028
CL=$(echo "\033[m")

# Telemetry
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "pve-lxc-system-admin" "pve"

NODE=$(hostname)

header_info
whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE LXC System Admin" --yesno "This will maintain passwordless LXC System Admins with full SUDO Permissions and SSH Access via SSH Keys. Proceed?" 10 58

whiptail_menu "$(awk -F ':' '$3>=1000 && $7 == "/bin/bash" && NR>1 {print $1 " " $2 ":" $3 ":" $4 ":" $5 ":" $6 ":" $7}' /etc/passwd)"
MENU_ARRAY+=("" "Create a new User" "OFF")

USER_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Users on ${NODE}" --radiolist "\nSelect a User to maintain as a System Admin on LXCs:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${MENU_ARRAY[@]}" 3>&1 1>&2 2>&3 | tr -d '"')
[[ -z ${USER_NAME} ]] && add_node_user
USER_COMMENT=$(grep "${USER_NAME}" /etc/passwd | awk -F ':' '{print $5}')
USER_HOME=$(get_user_home "${USER_NAME}" "")

MENU_ARRAY=("Deploy" "Deploy UID and Public Key of User '${USER_NAME}'." "ON")
MENU_ARRAY+=("Create/Renew Key Pair" "Create/Renew Key Pair and Deploy Public Key of User '${USER_NAME}'." "OFF")
MENU_ARRAY+=("Delete" "Delete User '${USER_NAME}'." "OFF")
MENU_ARRAY+=("Show" "Show Private Key of User '${USER_NAME}'." "OFF")
MENU_ARRAY+=("Add Authorization" "Add Authorization for SSH access with Private Key of User '${USER_NAME}'." "OFF")
MENU_ARRAY+=("Remove Authorization" "Remove Authorization for SSH access with Private Key of User '${USER_NAME}'." "OFF")
USER_ACTION=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE LXC System Admin" --radiolist "Select Maintenance Option for User '${USER_NAME}':" 16 148 6 "${MENU_ARRAY[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

[[ -z ${USER_ACTION} ]] && echo -e "${BL}[ERROR]${GN} ${RD}No User Option selected!${CL}\n" && exit

case ${USER_ACTION} in
("Deploy")
  USER_OPTION="Deploy UID and Public Key of User '${USER_NAME}'"
  [[ -f ${USER_HOME}/.ssh/authorized_keys ]] || keygen_node_user "${USER_NAME}" "New Key"
  ;;
("Create/Renew Key Pair")
  USER_OPTION="Deploy UID and Public Key of User '${USER_NAME}'"
  keygen_node_user "${USER_NAME}"
  ;;
("Delete")
  USER_OPTION="Delete User '${USER_NAME}'"
  delete_user "${USER_NAME}" ""
  ;;
("Show")
  USER_OPTION="Show Private Key of User '${USER_NAME}'"
  show_private_key "${USER_NAME}"
  ;;
("Add Authorization")
  USER_OPTION="Add Authorization for SSH access with Private Key of User '${USER_NAME}'"
  echo -e "${BL}[Info]${GN} ${USER_OPTION}:${CL}\n"
  authorization "${USER_NAME}" "add"
  ;;
("Remove Authorization")
  USER_OPTION="Remove Authorization for SSH access with Private Key of User '${USER_NAME}''"
  echo -e "${BL}[Info]${GN} ${USER_OPTION}:${CL}\n"
  authorization "${USER_NAME}" "remove"
  ;;
*)
  echo -e "${BL}[ERROR]${GN} ${RD}Unsupported Option!${CL}\n" && exit
  ;;
esac

if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Skip Not-Running Containers" --yesno "Do you want to skip containers that are not currently running?" 10 58; then
  SKIP_STOPPED="yes"
else
  SKIP_STOPPED="no"
fi

whiptail_menu "$(pct list | awk 'NR>1')"
excluded_containers=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Containers on ${NODE}" --checklist "\nSelect containers to skip from modifications:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${MENU_ARRAY[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

echo -e "${BL}[Info]${GN} ${USER_OPTION}:${CL}\n"
for container in $(pct list | awk '{if(NR>1) print $1}'); do
  #if [[ " ${excluded_containers[@]} " =~ " ${container} " ]]; then
  # shellcheck disable=SC2199
  if [[ ${excluded_containers[@]} =~ ${container} ]]; then
    echo -e "${BL}[Info]${GN} --- Skipping ${BL}${container}${CL}"
  else
    status=$(pct status "${container}")
    if [ "$SKIP_STOPPED" == "yes" ] && [ "$status" == "status: stopped" ]; then
      echo -e "${BL}[Info]${GN} --- Skipping ${BL}${container}${CL}${GN} (not running)${CL}"
      continue
    fi
    template=$(pct config "${container}" | grep -q "template:" && echo "true" || echo "false")
    if [ "$template" == "false" ] && [ "$status" == "status: stopped" ]; then
      echo -e "${BL}[Info]${GN} --- Starting${BL} ${container} ${CL}"
      pct start "${container}"
      echo -e "${BL}[Info]${GN} --- Waiting For${BL} ${container}${CL}${GN} To Start ${CL}"
      sleep 5
      if [ "${USER_ACTION}" == "Delete" ]; then
        delete_user "${USER_NAME}" "${container}"
      else
        maintain_container_user "${USER_NAME}" "${USER_COMMENT}" "${container}"
      fi
      echo -e "${BL}[Info]${GN} --- Shutting down${BL} ${container} ${CL}"
      pct shutdown "${container}" --timeout 180 &
    elif [ "$status" == "status: running" ]; then
      if [ "${USER_ACTION}" == "Delete" ]; then
        delete_user "${USER_NAME}" "${container}"
      else
        maintain_container_user "${USER_NAME}" "${USER_COMMENT}" "${container}"
      fi
    fi
  fi
done
wait
echo -e "\n${GN}The process of ${USER_OPTION} is complete, and the containers have been successfully modified.${CL}\n"
