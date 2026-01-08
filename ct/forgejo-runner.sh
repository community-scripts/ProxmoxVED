#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2026
# Author: Simon Friedrich
# License: MIT
# Source: https://forgejo.org/

APP="Forgejo Runner"
var_tags="${var_tags:-ci}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"

# REQUIRED for Podman-in-LXC
var_unprivileged="1"
var_nesting="1"
var_keyctl="1"

# -------------------------------------------------
# Framework setup
# -------------------------------------------------
header_info "$APP"
variables
color
catch_errors

# -------------------------------------------------
# Description
# -------------------------------------------------
function description() {
  cat <<EOF
Forgejo Actions Runner using Podman (unprivileged LXC)

Required inputs:
- Forgejo Instance URL
- Forgejo Runner Registration Token

Requirements:
- unprivileged container
- nesting enabled
- keyctl enabled
- unconfined AppArmor profile
EOF
}

# -------------------------------------------------
# Update logic
# -------------------------------------------------
function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/forgejo-runner ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  msg_info "Stopping Forgejo Runner"
  systemctl stop forgejo-runner
  msg_ok "Stopped Forgejo Runner"

  msg_info "Fetching latest Forgejo Runner version"
  RELEASE=$(curl -fsSL https://code.forgejo.org/api/v1/repos/forgejo/runner/releases/latest \
    | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')

  msg_info "Updating Forgejo Runner to v${RELEASE}"
  curl -fsSL \
    "https://code.forgejo.org/forgejo/runner/releases/download/v${RELEASE}/forgejo-runner-linux-amd64" \
    -o /usr/local/bin/forgejo-runner

  chmod +x /usr/local/bin/forgejo-runner
  msg_ok "Updated Forgejo Runner"

  msg_info "Starting Forgejo Runner"
  systemctl daemon-reload
  systemctl start forgejo-runner
  msg_ok "Started Forgejo Runner"

  msg_ok "Update completed successfully!"
  exit
}

# -------------------------------------------------
# Install
# -------------------------------------------------
start
build_container
description

msg_ok "Completed successfully!"
echo -e "${INFO}${YW}Forgejo Runner is now online and ready.${CL}"