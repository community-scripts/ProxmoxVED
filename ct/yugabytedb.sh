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
rm "/etc/pve/lxc/${CTID}.conf.backup"

# Enable yugabytedb script
pct exec "$CTID" -- systemctl enable "${NSAPP}".service

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:15433${CL}"
