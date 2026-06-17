#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://netbird.io

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add \
  bash \
  docker \
  docker-cli-compose \
  iproute2 \
  jq \
  newt \
  openssl
msg_ok "Installed Dependencies"

msg_info "Starting Docker"
rc-update add docker default >/dev/null
service docker start >/dev/null
msg_ok "Started Docker"

msg_info "Configuring NetBird Server"
mkdir -p /opt/netbird-server
cd /opt/netbird-server
cat <<EOF >netbird.env
NETBIRD_DOMAIN=${var_netbird_domain}
NETBIRD_AUTO_PROXY_TYPE=0
NETBIRD_AUTO_EMAIL=${var_netbird_email}
NETBIRD_AUTO_ENABLE_PROXY=false
NETBIRD_AUTO_ENABLE_CROWDSEC=false
EOF
curl -fsSL https://github.com/netbirdio/netbird/releases/latest/download/getting-started.sh \
  -o /opt/netbird-server/getting-started.sh
sed -i \
  -e 's/REVERSE_PROXY_TYPE=$(read_reverse_proxy_type)/REVERSE_PROXY_TYPE="${NETBIRD_AUTO_PROXY_TYPE:-$(read_reverse_proxy_type)}"/' \
  -e 's/TRAEFIK_ACME_EMAIL=$(read_traefik_acme_email)/TRAEFIK_ACME_EMAIL="${NETBIRD_AUTO_EMAIL:-$(read_traefik_acme_email)}"/' \
  -e 's/ENABLE_PROXY=$(read_enable_proxy)/ENABLE_PROXY="${NETBIRD_AUTO_ENABLE_PROXY:-$(read_enable_proxy)}"/' \
  -e 's/ENABLE_CROWDSEC=$(read_enable_crowdsec)/ENABLE_CROWDSEC="${NETBIRD_AUTO_ENABLE_CROWDSEC:-$(read_enable_crowdsec)}"/' \
  /opt/netbird-server/getting-started.sh
set -a
source /opt/netbird-server/netbird.env
set +a
$STD bash /opt/netbird-server/getting-started.sh
msg_ok "Configured NetBird Server"

motd_ssh
customize
cleanup_lxc
