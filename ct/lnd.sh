#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Hiago Dutra (hiagopdutra)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/lightningnetwork/lnd

APP="LND"
var_tags="${var_tags:-bitcoin;lightning}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  backup_lnd() {
    msg_info "Backing up Configuration"
    cp /opt/lnd/lnd.conf /opt/lnd.conf.bak
    [[ -d /opt/lnd/data ]] && cp -r /opt/lnd/data /opt/lnd-data.bak
    [[ -d /opt/lnd/backups ]] && cp -r /opt/lnd/backups /opt/lnd-backups.bak
    if [[ -n "$custom_scb_backup_dir" && "$custom_scb_backup_dir" != "/opt/lnd/backups" && -d "$custom_scb_backup_dir" ]]; then
      cp -r "$custom_scb_backup_dir" /opt/lnd-custom-backups.bak
    fi
    msg_ok "Backed up Configuration"
  }

  restore_lnd() {
    mkdir -p /opt/lnd/data /opt/lnd/backups
    cp /opt/lnd.conf.bak /opt/lnd/lnd.conf
    [[ -d /opt/lnd-data.bak ]] && cp -r /opt/lnd-data.bak/. /opt/lnd/data
    [[ -d /opt/lnd-backups.bak ]] && cp -r /opt/lnd-backups.bak/. /opt/lnd/backups
    if [[ -n "$custom_scb_backup_dir" && "$custom_scb_backup_dir" != "/opt/lnd/backups" && -d /opt/lnd-custom-backups.bak ]]; then
      mkdir -p "$custom_scb_backup_dir"
      cp -r /opt/lnd-custom-backups.bak/. "$custom_scb_backup_dir"
    fi
    rm -rf /opt/lnd.conf.bak /opt/lnd-data.bak /opt/lnd-backups.bak /opt/lnd-custom-backups.bak
  }

  backup_rtl() {
    [[ -f /opt/rtl/RTL-Config.json ]] && cp /opt/rtl/RTL-Config.json /opt/rtl-RTL-Config.json.bak
  }

  restore_rtl() {
    if [[ -f /opt/rtl-RTL-Config.json.bak ]]; then
      cp /opt/rtl-RTL-Config.json.bak /opt/rtl/RTL-Config.json
      rm -f /opt/rtl-RTL-Config.json.bak
    fi
  }

  update_rtl_files() {
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rtl" "Ride-The-Lightning/RTL" "tarball" "latest" "/opt/rtl"
    cd /opt/rtl
    $STD npm ci --omit=dev --legacy-peer-deps
  }

  update_lnd_files() {
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "lnd-app" "lightningnetwork/lnd" "prebuild" "latest" "/opt/lnd" "lnd-linux-amd64-*.tar.gz"
    install -m 755 /opt/lnd/lnd /usr/local/bin/lnd
    install -m 755 /opt/lnd/lncli /usr/local/bin/lncli
  }

  header_info
  check_container_storage
  check_container_resources
  local lnd_needs_update=0
  local rtl_needs_update=0
  local custom_scb_backup_dir=""

  if [[ ! -d /opt/lnd ]] || [[ ! -f /opt/lnd/lnd.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ -f /etc/lnd-scb-backup.env ]]; then
    source /etc/lnd-scb-backup.env
    custom_scb_backup_dir="${SCB_BACKUP_DIR:-}"
  fi

  if check_for_gh_release "lnd-app" "lightningnetwork/lnd"; then
    lnd_needs_update=1
  fi
  if [[ -d /opt/rtl ]] && check_for_gh_release "rtl" "Ride-The-Lightning/RTL"; then
    rtl_needs_update=1
  fi

  if [[ "$lnd_needs_update" == "1" && "$rtl_needs_update" == "1" ]]; then
    msg_info "Stopping Service"
    systemctl stop scb-backup 2>/dev/null || true
    systemctl stop rtl 2>/dev/null || true
    systemctl stop lnd
    msg_ok "Stopped Service"

    backup_lnd
    backup_rtl

    update_lnd_files
    restore_lnd
    update_rtl_files
    restore_rtl

    msg_info "Starting Service"
    systemctl start lnd
    [[ -f /opt/rtl/RTL-Config.json ]] && systemctl start rtl 2>/dev/null || true
    systemctl start scb-backup 2>/dev/null || true
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
    exit
  fi

  if [[ "$lnd_needs_update" == "1" ]]; then
    msg_info "Stopping Service"
    systemctl stop scb-backup 2>/dev/null || true
    systemctl stop rtl 2>/dev/null || true
    systemctl stop lnd
    msg_ok "Stopped Service"

    backup_lnd

    update_lnd_files
    restore_lnd

    msg_info "Starting Service"
    systemctl start lnd
    [[ -f /opt/rtl/RTL-Config.json ]] && systemctl start rtl 2>/dev/null || true
    systemctl start scb-backup 2>/dev/null || true
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
    exit
  fi

  if [[ "$rtl_needs_update" == "1" ]]; then
    if [[ ! -f /opt/rtl/RTL-Config.json ]]; then
      msg_error "No RTL Installation Found!"
      exit
    fi
    msg_info "Stopping Service"
    systemctl stop rtl
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    backup_rtl
    msg_ok "Backed up Configuration"

    update_rtl_files
    restore_rtl

    msg_info "Starting Service"
    systemctl start rtl
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} LND peer port:${CL}"
echo -e "${TAB}${BGN}9735${CL}"
