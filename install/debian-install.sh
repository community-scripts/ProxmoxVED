#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y gpg
msg_ok "Installed Dependencies"

#setup_mariadb

#FFMPEG_VERSION="n7.1.1" FFMPEG_TYPE="full" setup_ffmpeg

#fetch_and_deploy_gh_release "argus" "release-argus/Argus" "singlefile" "latest" "/opt/argus" "Argus-.*linux-amd64"
#fetch_and_deploy_gh_release "planka" "plankanban/planka" "prebuild" "latest" "/opt/planka" "planka-prebuild.zip"

#PYTHON_VERSION="3.12" setup_uv

#PHP_VERSION=8.2 PHP_FPM=YES setup_php
#setup_composer

# Example Setting for Test
#NODE_MODULE="pnpm@10.1,yarn"
#RELEASE=$(curl_handler -fsSL https://api.github.com/repos/babybuddy/babybuddy/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
#msg_ok "Get Release $RELEASE"
#NODE_VERSION="24" NODE_MODULE="yarn" setup_nodejs

#PG_VERSION="16" setup_postgresql

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
