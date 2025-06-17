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
#$STD apt-get install -y gnup
msg_ok "Installed Dependencies"

#fetch_and_deploy_gh_release "argus" "release-argus/Argus" "singlefile" "latest" "/opt/argus" "Argus-.*linux-amd64"
fetch_and_deploy_gh_release "planka" "plankanban/planka" "prebuild" "latest" "/opt/planka" "planka-prebuild.zip"

#PYTHON_VERSION="3.12" setup_uv

#echo -e "fetching healthchecks"
#fetch_and_deploy_gh_release "healthchecks" "healthchecks/healthchecks" "tarball" "latest" "/opt/healthchecks"
# minimal call: fetch_and_deploy_gh_release "healthchecks" "healthchecks/healthchecks" "tarball"
#echo -e "healthchecks done"

#echo -e "fetching defguard"
#fetch_and_deploy_gh_release "defguard" "DefGuard/defguard" "binary" "latest" "/opt/defguard"
# minimal call: fetch_and_deploy_gh_release "defguard" "DefGuard/defguard" "binary"
#echo -e "defguard done"

#PHP_VERSION=8.2 PHP_FPM=YES setup_php
#setup_composer

# Example Setting for Test
#NODE_MODULE="pnpm@10.1,yarn"
#RELEASE=$(curl_handler -fsSL https://api.github.com/repos/babybuddy/babybuddy/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
#msg_ok "Get Release $RELEASE"
#NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

#PG_VERSION="16" setup_postgresql
#MARIADB_VERSION="11.8"
#MYSQL_VERSION="8.0"

#install_mongodb
#setup_postgresql
#setup_mariadb
#install_mysql

# msg_info "Setup DISTRO env"
# DISTRO="$(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)"
# msg_ok "Setup DISTRO"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
