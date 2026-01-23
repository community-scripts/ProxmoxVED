#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/orhun/rustypaste

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "rustypaste" "orhun/rustypaste" "prebuild" "latest" "/opt/rustypaste" "*x86_64-unknown-linux-musl.tar.gz"
fetch_and_deploy_gh_release "rustypaste-cli" "orhun/rustypaste-cli" "prebuild" "latest" "/usr/local/bin" "*x86_64-unknown-linux-musl.tar.gz"

msg_info "Setting up RustyPaste"
cd /opt/rustypaste
sed -i 's|^address = ".*"|address = "0.0.0.0:8000"|' config.toml
msg_ok "Set up RustyPaste"

msg_info "Creating Service"
cat <<'EOF' >/etc/init.d/rustypaste
#!/sbin/openrc-run

name="rustypaste"
description="rustypaste Service"
directory="/opt/rustypaste"
command="/opt/rustypaste/rustypaste"
command_args=""
pidfile="/run/${RC_SVCNAME}.pid"
command_background="yes"
start_stop_daemon_args="--user root"

depend() {
	need net
}
EOF
chmod +x /etc/init.d/rustypaste
rc-update add rustypaste default
rc-service rustypaste start
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
