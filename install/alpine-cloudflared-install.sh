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

msg_info "Creating Cloudflared User"

# Enable sysctl service so conf is applied on start
$STD rc-update add sysctl
# Increase ping_group_range by one to create space for cloudflared group
cat <<EOF >/etc/sysctl.d/90-cloudflared.conf
# Increse ICMP ping_group_range
net.ipv4.ping_group_range = 65534 65535
EOF

# Apply 90-cloudflared.conf now
$STD sysctl -p /etc/sysctl.d/90-cloudflared.conf
# Create cloudflared group in ping_group_range
addgroup -g 65535 cloudflared
adduser -DH -s /sbin/nologin -G cloudflared cloudflared
msg_ok "Created Cloudflared User"

msg_info "Installing Cloudflared"
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
  mkdir -p "$CONFIG_PATH"
  # Create empty config file so permissions are correct and users can find it
  echo "tunnel: proxmoxve" >"$CONFIG_PATH/config.yml"
  chown -R cloudflared:cloudflared "$CONFIG_PATH"
  echo "command_args=\"tunnel --config $CONFIG_PATH/config.yml run proxmoxve\"" >>/etc/init.d/cloudflared
else
  echo "command_args=\"tunnel run --token $TOKEN\"" >>/etc/init.d/cloudflared
fi

cat <<EOF >>/etc/init.d/cloudflared
command_user="cloudflared"
command_background="yes"

start_pre() {
  checkpath -f -m 0644 -o "\$command_user:\$command_user" "/var/log/\$name.log"
  checkpath -f -m 0644 -o "\$command_user:\$command_user" "/var/log/\$name.err"
}
EOF

chmod +x /etc/init.d/cloudflared
msg_ok "Created Service"

msg_info "Enabling $APPLICATION service"
if $STD rc-update add cloudflared; then
  msg_ok "Enabled $APPLICATION service"
else
  msg_error "Failed to enable $APPLICATION service"
  exit 1
fi

# Start service now if externally managed, otherwise user needs to setup config first.
if [ -n "$TOKEN" ]; then
  msg_info "Starting $APPLICATION service"
  if $STD rc-service cloudflared start; then
    msg_ok "$APPLICATION service Running"
  else
    msg_error "Failed to start $APPLICATION service"
    cat /var/log/cloudflared.err
    exit 1
  fi
fi

motd_ssh
customize
cleanup_lxc
