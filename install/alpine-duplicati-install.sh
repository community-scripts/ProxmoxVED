#!/usr/bin/env bash

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add --no-cache duplicati
msg_ok "Installed duplicati"

msg_info "Enabling duplicati Service"
$STD rc-update add duplicati default || true
msg_ok "Enabled duplicati Service"

msg_info "Starting duplicati"
$STD rc-service duplicati start || true
msg_ok "Started duplicati"

motd_ssh
customize
