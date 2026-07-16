#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Kr1sCode
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Kr1sCode/proxmox-autosnap

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  python3 \
  python3-flask \
  python3-requests \
  python3-gunicorn \
  curl
msg_ok "Installed Dependencies"

msg_info "Installing proxmox-autosnap"
tmp_dir=$(mktemp -d)
curl -fsSL "https://github.com/Kr1sCode/proxmox-autosnap/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp_dir"
src=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
mkdir -p /opt/autosnap /etc/autosnap /var/lib/autosnap /var/log/autosnap
cp -r "$src"/app/. /opt/autosnap/
cp "$src"/systemd/*.service "$src"/systemd/*.timer /etc/systemd/system/
cat <<'JSON' >/etc/autosnap/config.json
{"settings":{"pve_host":"CHANGE_ME","pve_port":8006,"verify_tls":false,"paused":false},"auth":{"allowlist":["root@pam"]},"guests":{}}
JSON
python3 -c "import secrets; open('/etc/autosnap/secret','w').write(secrets.token_hex(32))"
chmod 600 /etc/autosnap/secret
rm -rf "$tmp_dir"
msg_ok "Installed proxmox-autosnap"

msg_info "Enabling Services"
systemctl enable -q --now autosnap-web.service
systemctl enable -q --now autosnap-scheduler.timer
msg_ok "Enabled Services"

motd_ssh
customize
cleanup_lxc
