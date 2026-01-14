#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: luismco
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/technomancer702/nodecast-tv

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "flatnotes" "dullage/flatnotes"
USE_UVX=YES setup_uv
setup_nodejs

msg_info "Installing Backend"
cd /opt/flatnotes
$STD /usr/local/bin/uv sync
$STD source .venv/bin/activate
$STD deactivate
msg_ok "Installed Backend"

msg_info "Installing Frontend"
cd /opt/flatnotes/client
$STD npm install
$STD npm run build
msg_ok "Installed Frontend"

motd_ssh
customize
cleanup_lxc
