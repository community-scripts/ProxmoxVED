#!/usr/bin/env ash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://openwrt.org/

set -eu

command -v uci >/dev/null 2>&1 || {
  printf '%s\n' "uci is required to configure OpenWrt networking" >&2
  exit 1
}

test -f /etc/config/network || {
  printf '%s\n' "/etc/config/network is required to configure OpenWrt networking" >&2
  exit 1
}

uci set network.lan='interface'
uci set network.lan.proto='static'
uci set network.lan.device='eth0'
uci set network.lan.ipaddr='192.168.1.1'
uci set network.lan.netmask='255.255.255.0'
uci set network.wan='interface'
uci set network.wan.proto='dhcp'
uci set network.wan.device='eth1'
uci commit network

if [ -x /etc/init.d/network ]; then
  /etc/init.d/network restart
fi
