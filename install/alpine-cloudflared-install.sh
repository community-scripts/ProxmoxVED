#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.cloudflare.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Creating Cloudflare User"

# Enable sysctl service
$STD rc-update add sysctl
cat <<EOF >/etc/sysctl.d/90-cloudflared.conf
# Increse ICMP ping_group_range
net.ipv4.ping_group_range = 65534 65535
EOF

$STD sysctl -p /etc/sysctl.d/90-cloudflared.conf
addgroup -g 65535 cloudflare
adduser -DH -s /sbin/nologin -G cloudflare cloudflare
msg_ok "Created Cloudflare User"

msg_info "Installing Cloudflared"
get_system_arch
fetch_and_deploy_gh_release cloudflared cloudflare/cloudflared singlefile latest /usr/bin "cloudflared-linux-$(get_system_arch)"
msg_ok "Installed Cloudflared"

msg_info "Creating Service"
cat <<EOF >/etc/init.d/cloudflared
#!/sbin/openrc-run

name="cloudflared"
pidfile="/run/\$name.pid"
output_log="/var/log/\$name.log"
error_log="/var/log/\$name.err"

command="/usr/bin/cloudflared"
EOF

if [ -z "$TOKEN" ]; then
  cloudflared tunnel create proxmoxve
  echo command_args="tunnel run --config /usr/local/etc/cloudflared/config.yml" >>/etc/init.d/cloudflared
else
  echo command_args="tunnel run --token $TOKEN" >>/etc/init.d/cloudflared
fi

cat <<EOF >/etc/init.d/cloudflared
command_user="cloudflare"
command_background="yes"

start_pre() {
  checkpath -f -m 0644 -o "\$command_user:\$command_user" "/var/log/\$name.log"
  checkpath -f -m 0644 -o "\$command_user:\$command_user" "/var/log/\$name.err"
}
EOF

msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
