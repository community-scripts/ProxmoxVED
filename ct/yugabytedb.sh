#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.yugabyte.com/yugabytedb/

# shellcheck source=misc/build.func
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# ====================================================================================
# YOU MUST SET THE CORRECT ULIMITS AND ENABLE TRANSPARENT HUGEPAGES ON YOUR SYSTEM
# ====================================================================================
#
# https://docs.yugabyte.com/stable/deploy/manual-deployment/system-config/#set-ulimits
#
#  - XFS is the recommended filesystem.
#  - ZFS and NFS are not currently supported.
#  - SSDs (solid state disks) are required.
#  - Do not use RAID across multiple disks.
# ====================================================================================

# App Default Values
APP="YugabyteDB"
var_tags="${var_tags:-database}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# Select most recent series
export YB_SERIES="v2025.2"

# Set yugabyte's home directory
export YB_HOME="/home/yugabyte"

# Make available to install script
export NSAPP

# prlimit settings for lxc config to match yugabyte requirements
lxc_prlimit_config=(
  "lxc.prlimit.core: unlimited"
  "lxc.prlimit.data: unlimited"
  "lxc.prlimit.fsize: unlimited"
  "lxc.prlimit.sigpending: 119934"
  "lxc.prlimit.memlock: 64"
  "lxc.prlimit.rss: unlimited"
  "lxc.prlimit.nofile: 1048576"
  "lxc.prlimit.msgqueue: 819200"
  "lxc.prlimit.cpu: unlimited"
  "lxc.prlimit.nproc: 12000"
  "lxc.prlimit.locks: unlimited"
)

header_info "$APP"
variables
color
catch_errors

valid_ip() {
  python3 -c "import ipaddress; ipaddress.ip_address('$1')" 2>/dev/null
}

valid_dns_label() {
  local l="$1"
  # Total length + DNS syntax check
  [[ ${#l} -ge 1 && ${#l} -le 63 && $l =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

valid_dns_name() {
  local name="$1"
  # Total length check (visible chars, no trailing dot)
  [[ ${#name} -ge 1 && ${#name} -le 253 ]] || return 1
  [[ $name != .* && $name != *. ]] || return 1
  IFS='.' read -ra parts <<<"$name"
  local p
  for p in "${parts[@]}"; do valid_dns_label "$p" || return 1; done
  return 0
}

config_yugabytedb() {
  TSERVER_FLAGS=""

  exit_script() {
    clear
    printf "\e[?25h"
    echo -e "\n${CROSS}${RD}User exited script${CL}\n"
    kill 0
    exit 1
  }

  local STEP=1
  local MAX_STEP=7
  while [ $STEP -le $MAX_STEP ]; do
    case $STEP in
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 1: Get CLOUD_LOCATION
    # ═══════════════════════════════════════════════════════════════════════════
    1)
      if CLOUD_LOCATION=$(
        whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
          --title "Cloud Location" \
          --ok-button "Next" --cancel-button "Exit" \
          --inputbox "Set your cloud location (e.g., aws.us-east-1.a):\n  💡 For on-premises, consider racks as zones to treat them as fault domains." \
          8 72 "$CLOUD_LOCATION" 3>&1 1>&2 2>&3
      ); then
        if [[ "$CLOUD_LOCATION" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
          ((STEP++))
        else
          if whiptail --msgbox "Invalid format. Use cloudprovider.region.zone (e.g., aws.us-east-1.a)." 7 74; then
            continue
          fi
        fi
      else
        exit_script
      fi
      ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 2: Join Cluster
    # ═══════════════════════════════════════════════════════════════════════════
    2)
      if
        whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
          --title "Join Cluster" \
          --defaultno \
          --yesno "Do want to join an existing cluster?" 7 40
      then
        # Get static IP
        local cluster_ip
        if cluster_ip=$(whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
          --title "Cluster Address" \
          --ok-button "Next" --cancel-button "Back" \
          --inputbox "Enter Cluster Address; A single IP address (v4 or v6) or DNS name" 7 69 "" \
          3>&1 1>&2 2>&3); then
          if valid_ip "$cluster_ip" || valid_dns_name "$cluster_ip"; then
            JOIN_CLUSTER="--join=${cluster_ip}"
            ((STEP++))
          else
            if whiptail --msgbox "Invalid Address. Examples: 192.168.1.100, 2001:0:0:0:0:0:0:1, example.com" 7 77; then
              continue
            fi
          fi
        else
          continue
        fi
      else
        if [ $? -eq 1 ]; then
          JOIN_CLUSTER=""
          ((STEP++))
        else
          ((STEP--))
          continue
        fi
      fi
      ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 3: Check if single AZ deployment
    # ═══════════════════════════════════════════════════════════════════════════
    3)
      local result
      if result=$(
        whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
          --title "Deployment Strategy" \
          --ok-button "Next" --cancel-button "Back" \
          --menu "\nSelect Deployment Strategy:" 9 84 2 \
          "Single-DC deployment" "Deploy YugabyteDB in a single region or private data center" \
          "Multi-DC deployment" "Deploy YugabyteDB across multiple data centers (DC)" \
          3>&1 1>&2 2>&3
      ); then

        if [[ "$result" == "Multi-DC deployment" ]]; then
          FAULT_TOLERANCE=$(whiptail --title "Radio list example" --radiolist \
            "Specify the fault tolerance for the universe." 11 93 4 \
            "none" "For single-node development, not production. Total data loss during outages" OFF \
            "zone" "Survives a single AZ/rack failure. Use when all replicas are in one region" ON \
            "region" "Use when geo-redundancy and disaster recovery are required" OFF \
            "cloud" "Provider-managed fault tolerance via cloud-level replication" OFF 3>&1 1>&2 2>&3) || result=$?
          if [ "$result" -ne 0 ]; then
            continue
          fi
          single_zone=false
          ((STEP++))
        else
          single_zone=true
          FAULT_TOLERANCE="zone"
          ((STEP++))
        fi
      else
        ((STEP--))
      fi
      ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 4: YSQL Connection Manager
    # ═══════════════════════════════════════════════════════════════════════════
    4)
      if whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
        --title "YSQL Connection Manager" \
        --yesno "Do want to use YSQL Connection Manager for connection pooling?\n  💡 Can take up to 200MB of RAM on each database node." \
        8 66; then
        enable_ysql_conn_mgr=true
      else
        if [ $? -eq 1 ]; then
          enable_ysql_conn_mgr=false
        else
          ((STEP--))
          continue
        fi
      fi
      ((STEP++))
      ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 5: Memory Defaults Optimized for YSQL
    # ═══════════════════════════════════════════════════════════════════════════
    5)
      if whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
        --title "Memory Defaults Optimized for YSQL" \
        --defaultno \
        --yesno "Do want to use memory defaults optimized for YSQL?\nSelect No to prioritize YCQL or if not using YSQL." 8 54; then
        mem_opt_for_ysql=true
      else
        if [ $? -eq 1 ]; then
          mem_opt_for_ysql=false
        else
          ((STEP--))
          continue
        fi
      fi
      ((STEP++))
      ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6: Backup/Restore Daemon
    # ═══════════════════════════════════════════════════════════════════════════
    6)
      if whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
        --title "Backup/Restore" \
        --yesno "Enable the backup/restore agent? (Enables yugabyted backup command)" 7 71; then
        BACKUP_DAEMON=true
      else
        if [ $? -eq 1 ]; then
          BACKUP_DAEMON=false
        else
          ((STEP--))
          continue
        fi
      fi
      ((STEP++))
      ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 7: Confirmation
    # ═══════════════════════════════════════════════════════════════════════════
    7)
      # Build summary
      TSERVER_FLAGS=""
      [[ "$single_zone" == true ]] && TSERVER_FLAGS+="durable_wal_write=true,"
      [[ "$enable_ysql_conn_mgr" == true ]] && TSERVER_FLAGS+="enable_ysql_conn_mgr=true,"
      [[ "$mem_opt_for_ysql" == true ]] && TSERVER_FLAGS+="use_memory_defaults_optimized_for_ysql=true,"

      local join_cluster=$(
        [ -z "${JOIN_CLUSTER:-}" ] && printf 'false' || printf "true\n  %s" "cluster_ip: $cluster_ip"
      )

      local tserver_flags="${TSERVER_FLAGS//,/$'\n'  }"
      local summary="When joining a cluster you must manually copy certificates between VMs, see:
https://docs.yugabyte.com/stable/deploy/manual-deployment/start-yugabyted

cloud_location:
  $CLOUD_LOCATION

join_cluster: $join_cluster

backup_daemon:
  $BACKUP_DAEMON

fault_tolerance:
  $FAULT_TOLERANCE

tserver_flags:
  $tserver_flags"

      if whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
        --title "CONFIRM SETTINGS" \
        --ok-button "OK" --cancel-button "Back" \
        --yesno "$summary\n\nCreate ${APP} with these settings?" 25 80; then
        ((STEP++))
      else
        ((STEP--))
      fi
      ;;
    esac
  done

  export TSERVER_FLAGS CLOUD_LOCATION BACKUP_DAEMON FAULT_TOLERANCE JOIN_CLUSTER
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d $YB_HOME ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_error "Currently we don't provide an update function for this ${APP}."
  exit
}

start
config_yugabytedb
build_container

msg_info "Stopping $CTID to apply config changes"
# Stop the container so ulimit changes can take effect
pct stop "$CTID"
for i in {1..10}; do
  if pct status "$CTID" | grep -q "status: stopped"; then
    msg_ok "Stopped LXC Container $CTID"
    break
  fi
  sleep 1
  if [ "$i" -eq 10 ]; then
    msg_error "LXC Container $CTID did not reach stopped state"
    exit 1
  fi
done

# Create a backup of the config file in the same directory and name it ${CTID}.conf.backup,
# then update the original if any legacy keys are used.
msg_info "Creating backup of /etc/pve/lxc/${CTID}.conf"
lxc-update-config -c "/etc/pve/lxc/${CTID}.conf"
if [ -f "/etc/pve/lxc/${CTID}.conf.backup" ]; then
  msg_ok "Created backup at /etc/pve/lxc/${CTID}.conf.backup"
else
  msg_error "Failed to create backup /etc/pve/lxc/${CTID}.conf.backup"
  exit 1
fi

msg_info "Updating $CTID config to match YugabyteDB guidelines"
# Append prlimit lxc config options to conf file
if [ -n "${lxc_prlimit_config[*]}" ]; then
  printf "%s\n" "${lxc_prlimit_config[@]}" >>"/etc/pve/lxc/${CTID}.conf"
fi

# Appends ,mountoptions=noatime to rootfs config if it's not already present
sed -i "/^rootfs: local-lvm:/{/mountoptions=noatime/! s/$/,mountoptions=noatime/}" /etc/pve/lxc/"${CTID}".conf

# Set swap to 0
sed -i -E 's/^(swap:[[:space:]]*)[0-9]+/\10/' /etc/pve/lxc/"${CTID}".conf
msg_ok "Updated $CTID config"

# Start the container
msg_info "Starting $CTID"
pct start "$CTID"
for i in {1..10}; do
  if pct status "$CTID" | grep -q "status: running"; then
    msg_ok "Started LXC Container $CTID"
    break
  fi
  sleep 1
  if [ "$i" -eq 10 ]; then
    msg_error "LXC Container $CTID did not reach running state"
    exit 1
  fi
done

# Remove backup
msg_info "Removing backup /etc/pve/lxc/${CTID}.conf.backup"
rm "/etc/pve/lxc/${CTID}.conf.backup"
msg_ok "Removed backup /etc/pve/lxc/${CTID}.conf.backup"

msg_info "Enable ${NSAPP}.service"
pct exec "$CTID" -- systemctl enable --quiet "${NSAPP}".service
msg_ok "Enabled ${NSAPP}.service"

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:15433${CL}"
echo -e "${BOLD}${INFO}${YWB}You must restart proxmox to fix the shmem mount permissions preventing YugabyteDB from starting${CL}"
