#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: angusmaul
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://orb.net/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Orb publishes an official apt repository. The suite is literally "orb" rather than a
# Debian codename, so one suite serves every release and there is no codename to keep in
# sync. Architectures is deliberately omitted: amd64 and arm64 both live in "main", so apt
# resolves whichever the container is.
setup_deb822_repo \
  "orb" \
  "https://pkgs.orb.net/stable/debian/orbforge.noarmor.gpg" \
  "https://pkgs.orb.net/stable/debian" \
  "orb" \
  "main"

msg_info "Installing Orb"
$STD apt install -y orb
msg_ok "Installed Orb"

# The package ships orb.service and its postinst enables and starts it, creating the
# system user "orb" with a home of /home/orb. The unit runs /usr/bin/orb sensor as that
# user with AmbientCapabilities=CAP_NET_RAW, which works in an unprivileged container.
msg_info "Enabling Service"
$STD systemctl enable --now orb
msg_ok "Enabled Service"

# orb-update.timer ships with the package but is deliberately left disabled. Updates go
# through the CT script's update option instead: /usr/bin/orb-update passes
# Dir::Etc::sourcelist=sources.list.d/orb.list, the legacy one-line source, so it would
# refresh nothing against the deb822 orb.sources written above.

motd_ssh
customize
cleanup_lxc
