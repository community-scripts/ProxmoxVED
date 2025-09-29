#!/usr/bin/env bash
#source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# DEV: use your fork/branch while testing
source <(curl -s https://raw.githubusercontent.com/Marfnl/ProxmoxVE/refs/heads/feature/blackbox-exporter/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Marfnl
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/prometheus/blackbox_exporter

# App Default Values
APP="Prometheus-Blackbox-Exporter"
var_tags="${var_tags:-monitoring;prometheus}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

# App output & base settings
header_info "$APP"
variables
color
catch_errors

# Update function
function update_script() {
  # Function Header
  header_info
  check_container_storage
  check_container_resources

  # Check if installation is present | -f for file, -d for folder
  if ! dpkg -s prometheus-blackbox-exporter &>/dev/null && [[ ! -f "/opt/${APP}_version.txt" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Crawling the new version and checking whether an update is required
  current_file="/opt/${APP}_version.txt"
  current_ver="$( [ -f "$current_file" ] && cat "$current_file" || dpkg-query -W -f='${Version}\n' prometheus-blackbox-exporter 2>/dev/null || echo 0 )"
  candidate_ver="$(apt-cache policy prometheus-blackbox-exporter | awk '/Candidate:/ {print $2}')"

  if [[ -z "$candidate_ver" || "$candidate_ver" == "(none)" ]]; then
    msg_error "Could not determine candidate version from APT."
    exit
  fi

  if [[ ! -f "$current_file" ]] || dpkg --compare-versions "$candidate_ver" gt "$current_ver"; then

    # Execute Update
    msg_info "Updating ${APP} to v${candidate_ver}"
    $STD apt-get update
    $STD apt-get install -y --only-upgrade prometheus-blackbox-exporter

    # Starting Services
    $STD systemctl restart prometheus-blackbox-exporter

    # Cleaning up
    # (No temporary files to remove for APT-based update.)

    # Last Action
    echo "$candidate_ver" > "$current_file"
    msg_ok "Updated ${APP} to v${candidate_ver}"
  else
    msg_ok "No update required. ${APP} is already at v${current_ver}."
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9115${CL}"
