#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://developer.hashicorp.com/nomad

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_deb822_repo \
  "hashicorp" \
  "https://apt.releases.hashicorp.com/gpg" \
  "https://apt.releases.hashicorp.com" \
  "$(get_os_info codename)" \
  "main"

msg_info "Installing Nomad"
$STD apt install -y nomad
msg_ok "Installed Nomad"

msg_info "Configuring Nomad"
mkdir -p /opt/nomad_data
cat <<EOF >/etc/nomad.d/nomad.hcl
datacenter = "dc1"
data_dir   = "/opt/nomad_data"
bind_addr  = "0.0.0.0"

advertise {
  http = "${LOCAL_IP}"
  rpc  = "${LOCAL_IP}"
  serf = "${LOCAL_IP}"
}

server {
  enabled          = true
  bootstrap_expect = 1
}

client {
  enabled = true
}

ui {
  enabled = true
}
EOF
systemctl enable -q --now nomad
msg_ok "Configured Nomad"

motd_ssh
customize
cleanup_lxc
