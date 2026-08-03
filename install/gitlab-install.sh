#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://about.gitlab.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  openssh-server \
  perl \
  tzdata
msg_ok "Installed Dependencies"

setup_deb822_repo \
  "gitlab-ce" \
  "https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey" \
  "https://packages.gitlab.com/gitlab/gitlab-ce/debian" \
  "$(get_os_info codename)" \
  "main"

msg_info "Installing GitLab CE (Patience)"
EXTERNAL_URL="http://${LOCAL_IP}" $STD apt install -y gitlab-ce
msg_ok "Installed GitLab CE"

motd_ssh
customize
cleanup_lxc
