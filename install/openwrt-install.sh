#!/usr/bin/env ash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Mihael Zamin Sousa (mihazs)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://openwrt.org/

lan_ipaddr="${OPENWRT_LAN_IPADDR:-${var_lan_ipaddr:-192.168.1.1}}"
lan_netmask="${OPENWRT_LAN_NETMASK:-${var_lan_netmask:-255.255.255.0}}"

openwrt_update_package_feeds() {
  package_manager="$1"
  attempt=1
  max_attempts=6

  while [ "$attempt" -le "$max_attempts" ]; do
    if "$package_manager" update; then
      return 0
    fi

    if [ "$attempt" -lt "$max_attempts" ]; then
      printf 'OpenWrt package feed update failed; retrying in 5 seconds (%s/%s)\n' "$attempt" "$max_attempts" >&2
      sleep 5
    fi
    attempt=$((attempt + 1))
  done

  printf '%s\n' "OpenWrt package feed update failed after applying network configuration; verify WAN bridge, DHCP, DNS, and internet connectivity" >&2
  return 1
}

uci set network.lan='interface' &&
  uci set network.lan.proto='static' &&
  uci set network.lan.device='eth0' &&
  uci set network.lan.ipaddr="$lan_ipaddr" &&
  uci set network.lan.netmask="$lan_netmask" &&
  uci set network.wan='interface' &&
  uci set network.wan.proto='dhcp' &&
  uci set network.wan.device='eth1' &&
  uci commit network || exit 1

/etc/init.d/network reload >/dev/null 2>&1 || printf '%s\n' "OpenWrt network reload failed; package feed update will verify connectivity" >&2

var_interface="${OPENWRT_INTERFACE:-${var_interface:-yes}}"
var_interface_packages="${OPENWRT_INTERFACE_PACKAGES:-${var_interface_packages:-luci}}"

case "$var_interface" in
yes | true | 1 | on)
  set --
  for interface_package in $var_interface_packages; do
    interface_package="${interface_package##*/}"
    if [ -n "$interface_package" ]; then
      set -- "$@" "$interface_package"
    fi
  done

  if [ "$#" -eq 0 ]; then
    printf '%s\n' "At least one OpenWrt interface package is required when var_interface is enabled" >&2
    exit 1
  fi

  if command -v opkg >/dev/null 2>&1; then
    openwrt_update_package_feeds opkg || exit 1
    opkg install "$@" || exit 1
  elif command -v apk >/dev/null 2>&1; then
    openwrt_update_package_feeds apk || exit 1
    apk add "$@" || exit 1
  else
    printf '%s\n' "opkg or apk is required to install OpenWrt interface packages" >&2
    exit 1
  fi

  if [ -x /etc/init.d/uhttpd ]; then
    /etc/init.d/uhttpd enable || exit 1
    /etc/init.d/uhttpd start || exit 1
  fi
  ;;
no | false | 0 | off)
  ;;
*)
  printf '%s\n' "var_interface must be yes or no" >&2
  exit 1
  ;;
esac
