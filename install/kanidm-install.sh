#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://kanidm.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  clang \
  lld \
  pkg-config \
  libssl-dev \
  libpam0g-dev \
  libudev-dev \
  libsystemd-dev
msg_ok "Installed Dependencies"

setup_rust

fetch_and_deploy_gh_release "kanidm" "kanidm/kanidm" "tarball"

msg_info "Building Kanidm Server (Patience)"
cd /opt/kanidm
export KANIDM_BUILD_PROFILE=release_linux
$STD cargo build --release --locked --bin kanidmd
install -m 0755 target/release/kanidmd /usr/local/sbin/kanidmd
mkdir -p /usr/share/kanidm/ui/hpkg
cp -r server/core/static/. /usr/share/kanidm/ui/hpkg/
msg_ok "Built Kanidm Server"

msg_info "Generating Self-Signed Certificate"
create_self_signed_cert "kanidm"
msg_ok "Generated Self-Signed Certificate"

msg_info "Configuring Kanidm"
mkdir -p /etc/kanidm /var/lib/kanidm
cat <<EOF >/etc/kanidm/server.toml
version = "2"
bindaddress = "0.0.0.0:8443"
db_path = "/var/lib/kanidm/kanidm.db"
tls_chain = "/etc/ssl/kanidm/kanidm.crt"
tls_key = "/etc/ssl/kanidm/kanidm.key"
domain = "kanidm.${LOCAL_IP}.nip.io"
origin = "https://kanidm.${LOCAL_IP}.nip.io:8443"
log_level = "info"
EOF
chmod 600 /etc/kanidm/server.toml
chmod 640 /etc/ssl/kanidm/kanidm.key
msg_ok "Configured Kanidm"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/kanidm.service
[Unit]
Description=Kanidm Identity Management Server
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=root
RuntimeDirectory=kanidmd
RuntimeDirectoryMode=0755
StateDirectory=kanidm
StateDirectoryMode=0750
ExecStart=/usr/local/sbin/kanidmd server -c /etc/kanidm/server.toml
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
LimitNOFILE=65536
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now kanidm
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
