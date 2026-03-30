#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://openthread.io/guides/border-router

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  cmake \
  ninja-build \
  pkg-config \
  git \
  iproute2 \
  libreadline-dev \
  libncurses-dev \
  rsyslog \
  dbus \
  libdbus-1-dev \
  libjsoncpp-dev \
  iptables \
  ipset \
  bind9 \
  libnetfilter-queue1 \
  libnetfilter-queue-dev \
  libprotobuf-dev \
  protobuf-compiler \
  nodejs \
  npm
msg_ok "Installed Dependencies"

msg_info "Cloning OpenThread Border Router"
# git clone is needed to fetch submodules, fetch_and_deploy_gh_release doesn't support this. We use --depth 1 to minimize the amount of data cloned, but it still may take a while.
$STD git clone --depth 1 https://github.com/openthread/ot-br-posix /opt/ot-br-posix
cd /opt/ot-br-posix
$STD git submodule update --depth 1 --init --recursive
msg_ok "Cloned OpenThread Border Router"

msg_info "Building OpenThread Border Router (Patience)"
mkdir -p build && cd build
$STD cmake -GNinja \
  -DBUILD_TESTING=OFF \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DOTBR_DBUS=ON \
  -DOTBR_MDNS=openthread \
  -DOTBR_REST=ON \
  -DOTBR_WEB=ON \
  -DOTBR_BORDER_ROUTING=ON \
  -DOTBR_BACKBONE_ROUTER=ON \
  -DOT_FIREWALL=ON \
  -DOT_POSIX_NAT64_CIDR="192.168.255.0/24" \
  ..
$STD ninja
$STD ninja install
msg_ok "Built OpenThread Border Router"

msg_info "Configuring Network"
cat <<EOF >/etc/sysctl.d/99-otbr.conf
net.ipv6.conf.all.forwarding=1
net.ipv4.ip_forward=1
EOF
$STD sysctl -p /etc/sysctl.d/99-otbr.conf
msg_ok "Configured Network"

msg_info "Configuring Services"
cat <<EOF >/etc/default/otbr-agent
OTBR_AGENT_OPTS="-I wpan0 -B eth0 spinel+hdlc+uart:///dev/ttyACM0"
EOF
systemctl enable -q --now otbr-agent otbr-web
msg_ok "Configured Services"

motd_ssh
customize
cleanup_lxc
