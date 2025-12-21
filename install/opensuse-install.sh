#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/GoldenSpringness/ProxmoxVED/raw/main/LICENSE
# Source: https://www.opensuse.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

motd_ssh
customize
cleanup_lxc
