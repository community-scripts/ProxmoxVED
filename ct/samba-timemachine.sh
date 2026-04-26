#!/usr/bin/env bash
# shellcheck source=/dev/null
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: YOUR_GITHUB_USERNAME
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.samba.org/

APP="Samba Time Machine"
# shellcheck disable=SC2034
var_tags="backup;nas;timemachine;samba"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

# ─── Storage backend selection ───────────────────────────────────────────────
function select_storage_backend() {
  STORAGE_TYPE=$(whiptail --title "Storage Backend" \
    --menu "Choose how backups will be stored:" 15 60 3 \
    "zfs"  "ZFS dataset bind mount (recommended)" \
    "dir"  "Directory inside LXC disk" \
    "nfs"  "NFS mount from another server" \
    3>&1 1>&2 2>&3) || exit 1

  case "$STORAGE_TYPE" in
    zfs)
      ZFS_DATASET=$(whiptail --title "ZFS Dataset" \
        --inputbox "ZFS dataset path on the Proxmox host:\n(e.g. tank/timemachine)" \
        10 60 "tank/timemachine" \
        3>&1 1>&2 2>&3) || exit 1

      if ! zfs list "$ZFS_DATASET" &>/dev/null; then
        if whiptail --yesno "Dataset '$ZFS_DATASET' does not exist. Create it?" 8 60; then
          zfs create "$ZFS_DATASET" || { echo "Failed to create ZFS dataset"; exit 1; }
        else
          exit 1
        fi
      fi
      ;;

    nfs)
      NFS_SERVER=$(whiptail --title "NFS Server" \
        --inputbox "NFS server address:" \
        8 60 "" 3>&1 1>&2 2>&3) || exit 1
      NFS_SHARE=$(whiptail --title "NFS Share" \
        --inputbox "NFS share path (e.g. /volume1/backups):" \
        8 60 "" 3>&1 1>&2 2>&3) || exit 1
      ;;
  esac

  TM_QUOTA=$(whiptail --title "Time Machine Quota" \
    --inputbox "Maximum size for Time Machine backups (e.g. 500G, 2T):" \
    8 60 "1T" \
    3>&1 1>&2 2>&3) || exit 1

  TM_PASSWORD=$(whiptail --title "Samba Password" \
    --passwordbox "Password for the 'timemachine' Samba user:\n(leave empty for guest/no-password access)" \
    10 60 "" 3>&1 1>&2 2>&3) || exit 1

  DASHBOARD=$(whiptail --title "Web Dashboard" \
    --yesno "Install the PHP web dashboard?\n(requires php-cli, accessible on port 8080)" \
    8 60 && echo "yes" || echo "no")
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/samba/smb.conf ]] || ! grep -q "TimeMachine" /etc/samba/smb.conf; then
    msg_error "No ${APP} installation found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Updated ${APP} LXC"
  msg_ok "Updated successfully!"
  exit
}

# ─── Advanced mode hook ───────────────────────────────────────────────────────
# Called by build.func when user selects advanced mode
function advanced_settings() {
  select_storage_backend
}

# ─── Default mode ─────────────────────────────────────────────────────────────
function default_settings() {
  STORAGE_TYPE="dir"
  TM_QUOTA="1T"
  TM_PASSWORD=""
  DASHBOARD="no"
}

start
build_container

# ─── Post-container setup (host side) ────────────────────────────────────────
CTID=$(cat /tmp/.community-scripts.ctid 2>/dev/null || echo "$CTID")

case "$STORAGE_TYPE" in
  zfs)
    msg_info "Configuring ZFS bind mount for dataset '$ZFS_DATASET'"
    # Fix ownership for unprivileged LXC (uid map 0→100000)
    chown 100000:100000 "/$ZFS_DATASET"
    chmod 777 "/$ZFS_DATASET"
    # Add bind mount to LXC config
    echo "mp0: /$ZFS_DATASET,mp=/mnt/timemachine" >> "/etc/pve/lxc/${CTID}.conf"
    msg_ok "ZFS bind mount configured"
    # Restart the container to apply the bind mount
    pct reboot "$CTID" &>/dev/null
    sleep 5
    ;;

  nfs)
    msg_info "Configuring NFS mount options in LXC"
    # NFS requires the 'nfs' feature in the LXC config
    echo "features: nesting=1,mount=nfs" >> "/etc/pve/lxc/${CTID}.conf"
    pct reboot "$CTID" &>/dev/null
    sleep 5
    ;;

  dir)
    msg_info "Using local directory storage (inside LXC disk)"
    ;;
esac

# Pass configuration to the install script via a temp file inside the container
pct exec "$CTID" -- bash -c "mkdir -p /tmp/tm-setup"
pct exec "$CTID" -- bash -c "cat > /tmp/tm-setup/config.env <<EOF
TM_STORAGE_TYPE='${STORAGE_TYPE}'
TM_QUOTA='${TM_QUOTA}'
TM_PASSWORD='${TM_PASSWORD}'
TM_NFS_SERVER='${NFS_SERVER:-}'
TM_NFS_SHARE='${NFS_SHARE:-}'
TM_DASHBOARD='${DASHBOARD}'
EOF"

description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access the dashboard (if enabled): http://$(pct exec "$CTID" -- hostname -I | awk '{print $1}'):8080${CL}"
