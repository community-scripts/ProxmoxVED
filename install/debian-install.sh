#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source:

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_hwaccel

msg_info "Installing Base Dependencies"
$STD apt install -y curl wget ca-certificates
msg_ok "Installed Base Dependencies"

setup_imagemagick

# msg_info "Installing Proxmox Backup Server"
# setup_deb822_repo \
#   "proxmox-backup-server" \
#   "https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg" \
#   "http://download.proxmox.com/debian/pbs" \
#   "trixie" \
#   "pbs-no-subscription"

# export DEBIAN_FRONTEND=noninteractive
# export IFUPDOWN2_NO_IFRELOAD=1
# $STD apt install -y proxmox-backup-server
# msg_ok "Installed Proxmox Backup Server"

#RUST_PROFILE="minimal" RUST_TOOLCHAIN="stable" setup_rust

motd_ssh
customize
cleanup_lxc
