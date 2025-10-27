#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: JamesonRGrieve
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/frappe/erpnext

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Downloading ERPNext installer"
INSTALLER_URL="https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/install/erpnext-install.sh"
SCRIPT_PATH=$(mktemp)
trap 'rm -f "$SCRIPT_PATH"' EXIT
if ! curl -fsSL "$INSTALLER_URL" -o "$SCRIPT_PATH"; then
  msg_error "Failed to download ERPNext installer"
  exit 1
fi
chmod +x "$SCRIPT_PATH"
msg_ok "Downloaded ERPNext installer"

export FUNCTIONS_FILE_PATH
export ERPNEXT_ROLE="websocket"
export ERPNEXT_PARENT_INITIALIZED=1

bash "$SCRIPT_PATH"
EXIT_STATUS=$?
if [[ $EXIT_STATUS -ne 0 ]]; then
  msg_error "ERPNext websocket installation failed"
  exit $EXIT_STATUS
fi
exit 0
