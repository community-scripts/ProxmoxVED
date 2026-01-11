#!/usr/bin/env bash

# Copyright (c) 2021-2026 bandogora
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.yugabyte.com/yugabytedb/

# shellcheck source=misc/build.func
source <(curl -fsSL https://raw.githubusercontent.com/bandogora/ProxmoxVED/feature/yugabytedb/misc/build.func)
# source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

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
var_os="${var_os:-almalinux}"
var_version="${var_version:-9}"
var_unprivileged="${var_unprivileged:-1}"

# Select most recent series
export YB_SERIES="v2025.2"

# Set yugabyte's home directory
export YB_HOME="/home/yugabyte"

# Make available to install script
export NSAPP

# prlimit settings for lxc config to match yugabyte requirements
lxc_prlimit_config=(
  "lxc.prlimit.nofile = 1048576"
  "lxc.prlimit.sigpending = 119934"
)

header_info "$APP"
variables
color
catch_errors

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
  local MAX_STEP=6
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
          --inputbox "Set your cloud location (e.g., aws.us-east-1.a):\n  💡 For on-premises deployments, consider racks as zones to treat them\n    as fault domains." \
          8 80 "" 3>&1 1>&2 2>&3
      ); then
        if [[ "$CLOUD_LOCATION" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
          ((STEP++))
        else
          whiptail --msgbox "Invalid format. Use cloudprovider.region.zone (e.g., aws.us-east-1.a)." 8 60
        fi
      else
        exit_script
      fi
      ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 2: Check if single AZ deployment
    # ═══════════════════════════════════════════════════════════════════════════
    2)
      if result=$(whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
        --title "Deployment Strategy" \
        --ok-button "Next" --cancel-button "Back" \
        --menu "\nSelect Deployment Strategy:" 12 82 2 \
        "Single-DC deployment" "| Deploy YugabyteDB in a single region or private data center" \
        "Multi-DC deployment" "| Deploy YugabyteDB across multiple data centers (DC)" \
        3>&1 1>&2 2>&3); then

        if [[ "$result" == "Multi-DC deployment" ]]; then
          FAULT_TOLERANCE=$(whiptail --title "Radio list example" --radiolist \
            "Specify the fault tolerance for the universe." 12 100 4 \
            "none" "Use when you run a single-node development instance or accept total data loss during outages. Not for production." OFF \
            "zone" "Recommended for intra-datacenter HA across multiple racks/availability zones within a single region. Survives a single AZ/rack failure with low cross-node latency. Use when you need high availability, low write latency, and all replicas are in one region." ON \
            "region" "Recommended for cross-region deployments where you need survivability against an entire AZ/region outage. Survives a full region failure (with appropriate replica placement) but increases write latency and cross-region bandwidth cost. Use when geo-redundancy and disaster recovery are required." OFF \
            "cloud" "Use when you want provider-managed multi-region/multi-cloud fault tolerance via cloud-level replication (e.g., cloud-managed clusters across providers or availability domains). Use if you prefer offloading replication/failover complexity to cloud services or need resilience across cloud providers." OFF 3>&1 1>&2 2>&3)
          ((STEP++))
        else
          TSERVER_FLAGS+="durable_wal_write=true,"
          FAULT_TOLERANCE="zone"
          ((STEP++))
        fi
      else
        ((STEP--))
      fi
      ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 3: YSQL Connection Manager
    # ═══════════════════════════════════════════════════════════════════════════
    3)
      if whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
        --title "YSQL Connection Manager" \
        --yesno "Do want to use YSQL Connection Manager for connection pooling?" 8 80; then
        TSERVER_FLAGS+="enable_ysql_conn_mgr=true,"
      else
        if [ $? -eq 1 ]; then
          true
        else
          ((STEP--))
          continue
        fi
      fi
      ((STEP++))
      ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 4: Memory Defaults Optimized for YSQL
    # ═══════════════════════════════════════════════════════════════════════════
    4)
      if whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
        --title "Memory Defaults Optimized for YSQL" \
        --defaultno \
        --yesno "Do want to use memory defaults optimized for YSQL?" 8 80; then
        TSERVER_FLAGS+="use_memory_defaults_optimized_for_ysql=true,"
      else
        if [ $? -eq 1 ]; then
          true
        else
          ((STEP--))
          continue
        fi
      fi
      ((STEP++))
      ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 5: Backup/Restore Daemon
    # ═══════════════════════════════════════════════════════════════════════════
    5)
      if whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
        --title "Backup/Restore" \
        --yesno "Enable the backup/restore agent? (Enables yugabyted backup command)" 8 80; then
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
    # STEP 6: Confirmation
    # ═══════════════════════════════════════════════════════════════════════════
    6)
      # Build summary
      local tserver_flags="${TSERVER_FLAGS//,/\n}"
      local summary="
cloud_location:
  $CLOUD_LOCATION

backup_daemon:
  $BACKUP_DAEMON

fault_tolerance:
  $FAULT_TOLERANCE

tserver_flags:
  $tserver_flags"

      if whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
        --title "CONFIRM SETTINGS" \
        --cancel-button "Back" \
        --yesno "$summary\nCreate ${APP} with these settings?" 32 80; then
        ((STEP++))
      else
        ((STEP--))
      fi
      ;;
    esac
  done

  # 3)
  # if whiptail --backtitle "YugabyteDB Setup [Step $STEP/$MAX_STEP]" \
  #   --title "Single AZ deployment" \
  #   --yesno "Single availability zone (AZ) deployment?" 8 80; then
  #   TSERVER_FLAGS+="durable_wal_write=true"
  # else
  #   if [ $? -eq 0 ]; then
  #     ((STEP--))
  #     continue
  #   fi
  # fi
  # ((STEP++))
  # ;;

  # prompt() {
  #   local out rc
  #   out=$(whiptail --title "YugabyteDB Setup" --inputbox \
  #     "Set your cloud location (e.g., aws.us-east-1.a):\n  💡 For on-premises deployments, consider racks as zones to treat them\n    as fault domains." \
  #     10 80 3>&1 1>&2 2>&3)
  #   # If user cancelled, emit nothing and set CLOUD_LOCATION empty, but return 0
  #   CLOUD_LOCATION="$out"
  #   # Normalize: treat cancel as handled here (do not let non‑zero escape)
  #   return 0
  # }

  # prompt() {
  #   local out rc
  #   # Capture whiptail stdout via a pipe, keep /dev/tty for terminal I/O
  #   out=$({ whiptail --title "YugabyteDB Setup" \
  #     --inputbox "Set your cloud location (e.g., aws.us-east-1.a):\n  💡 For on-premises deployments, consider racks as zones to treat them\n    as fault domains." \
  #     10 80; } </dev/tty 2>&1) || rc=$?
  #   # Whiptail writes selection to stdout (captured), and prints control sequences to tty
  #   CLOUD_LOCATION=$out
  #   # Drain any bytes from /dev/tty (non-blocking) to remove leftover newline/control seqs
  #   while read -r -t 0.01 -n 1 _ </dev/tty 2>/dev/null; do :; done
  #   return ${rc:-0}
  # }

  # validate() {
  #   local v="$1"
  #   [[ $v =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]
  # }

  # while true; do
  #   prompt
  #   if [ -z "$CLOUD_LOCATION" ]; then
  #     echo "${CROSS}Script aborted: You must set your cloud location"
  #     exit 0
  #   fi
  #   if validate "$CLOUD_LOCATION"; then break; fi
  #   whiptail --title "YugabyteDB Setup" \
  #     --msgbox "Invalid format. Use cloudprovider.region.zone (e.g., aws.us-east-1.a)." 8 60
  # done

  # if single_zone=$(whiptail --title "YugabyteDB Setup" \
  #   --yesno "Single availability zone (AZ) deployment?" 8 80); then
  #   TSERVER_FLAGS+="durable_wal_write=true"
  # fi

  # if [[ $single_zone -eq 0 ]]; then
  #   FAULT_TOLERANCE=$(whiptail --title "Radio list example" --radiolist \
  #     "Specify the fault tolerance for the universe." 6 80 4 \
  #     "none" "Use when you run a single-node development instance or accept total data loss during outages. Not for production." OFF \
  #     "zone" "Recommended for intra-datacenter HA across multiple racks/availability zones within a single region. Survives a single AZ/rack failure with low cross-node latency. Use when you need high availability, low write latency, and all replicas are in one region." ON \
  #     "region" "Recommended for cross-region deployments where you need survivability against an entire AZ/region outage. Survives a full region failure (with appropriate replica placement) but increases write latency and cross-region bandwidth cost. Use when geo-redundancy and disaster recovery are required." OFF \
  #     "cloud" "Use when you want provider-managed multi-region/multi-cloud fault tolerance via cloud-level replication (e.g., cloud-managed clusters across providers or availability domains). Use if you prefer offloading replication/failover complexity to cloud services or need resilience across cloud providers." OFF 3>&1 1>&2 2>&3)
  # fi

  # if whiptail --title "YugabyteDB Setup" --yesno "Is this a single zone setup?" 8 80; then
  #   # In single AZ deployments, you need to set the yb-tserver flag --durable_wal_write=true
  #   # to not lose data if the whole data center goes down (for example, power failure).
  #   TSERVER_FLAGS+="durable_wal_write=true,"
  # fi

  # if ! whiptail --title "YugabyteDB Setup" \
  #   --yesno "Do want to use YSQL Connection Manager for connection pooling?" 8 80; then
  #   TSERVER_FLAGS+="enable_ysql_conn_mgr=true,"
  # fi

  # if whiptail --title "YugabyteDB Setup" \
  #   --yesno "Do want to use memory defaults optimized for YSQL?" 8 80 --defaultno; then
  #   TSERVER_FLAGS+="use_memory_defaults_optimized_for_ysql=true,"
  # fi

  # if ! whiptail --title "YugabyteDB Setup" \
  #   --yesno "Enable the backup/restore agent? (Enables yugabyted backup command)" 8 80; then
  #   BACKUP_DAEMON=false
  # fi

  export TSERVER_FLAGS CLOUD_LOCATION BACKUP_DAEMON FAULT_TOLERANCE
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Check if installation is present
  if [[ ! -d $YB_HOME ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Crawling the new version and checking whether an update is required
  read -r VERSION RELEASE < <(
    curl -fsSL https://github.com/yugabyte/yugabyte-db/raw/refs/heads/master/docs/data/currentVersions.json |
      jq -r ".dbVersions[] | select(.series == \"${YB_SERIES}\") | [.version, .appVersion] | @tsv"
  )
  # Get version_number and build_number then concat with '-' to match .appVersion style stored in RELEASE
  if [[ "${RELEASE}" != "$(sed -rn 's/.*"version_number"[[:space:]]*:[[:space:]]*"([^"]*)".*"build_number"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1-\2/p' ${YB_HOME}/version_metadata.json)" ]]; then
    # Stopping Services
    msg_info "Stopping $APP"
    systemctl stop "${NSAPP}".service
    pkill yb-master
    msg_ok "Stopped $APP"

    # Creating Backup
    # msg_info "Creating Backup"
    # tar -czf "/opt/${NSAPP}_backup_$(date +%F).tar.gz" [IMPORTANT_PATHS]
    # msg_ok "Backup Created"

    msg_info "Updating Dependencies"
    $STD dnf -y upgrade
    alternatives --install /usr/bin/python python /usr/bin/python3.11 99
    alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 99
    # Set working dir
    cd "$YB_HOME" || exit
    source .venv/bin/activate
    $STD uv self update
    $STD uv pip install --upgrade pip
    $STD uv pip install --upgrade lxml
    $STD uv pip install --upgrade s3cmd
    $STD uv pip install --upgrade psutil
    msg_ok "Updated Dependencies"

    # Execute Update
    msg_info "Updating $APP to v${RELEASE}"

    # Get latest version and build number for our series
    curl -OfsSL "https://software.yugabyte.com/releases/${VERSION}/yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"

    tar -xf "yugabyte-${RELEASE}-linux-$(uname -m).tar.gz" --strip 1
    rm -rf "yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"
    # Run post install
    ./bin/post_install.sh
    tar -xf share/ybc-*.tar.gz
    rm -rf ybc-*/conf/
    msg_ok "Updated $APP to v${RELEASE}"

    # Starting Services
    msg_info "Starting ${NSAPP}.service"
    systemctl start "${NSAPP}".service
    # Verify service is running
    if systemctl is-active --quiet "${NSAPP}".service; then
      msg_ok "Started ${NSAPP}.service"
    else
      msg_error "Service failed to start"
      journalctl -u "${NSAPP}".service -n 20
      exit 1
    fi

    # Cleaning up
    msg_info "Cleaning Up"
    $STD dnf autoremove -y
    $STD dnf clean all
    $STD uv cache clean
    rm -rf \
      ~/.cache \
      "$YB_HOME/.cache" \
      /var/cache/yum \
      /var/cache/dnf
    msg_ok "Cleanup Completed"
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
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
