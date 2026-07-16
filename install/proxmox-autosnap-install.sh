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
$STD apt install -y \
  python3-flask \
  python3-requests \
  python3-gunicorn
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "proxmox-autosnap" "Kr1sCode/proxmox-autosnap" "tarball"

msg_info "Setting up proxmox-autosnap"
mkdir -p /etc/autosnap /var/lib/autosnap /var/log/autosnap
cat <<'JSON' >/etc/autosnap/config.json
{"settings":{"pve_host":"CHANGE_ME","pve_port":8006,"verify_tls":false,"paused":false},"auth":{"allowlist":["root@pam"]},"guests":{}}
JSON
python3 -c "import secrets; open('/etc/autosnap/secret','w').write(secrets.token_hex(32))"
chmod 600 /etc/autosnap/secret
msg_ok "Set up proxmox-autosnap"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/autosnap-web.service
[Unit]
Description=proxmox-autosnap web UI
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/proxmox-autosnap/app
ExecStart=/usr/bin/python3 -m gunicorn -w 2 -b 0.0.0.0:80 --timeout 120 web:app
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/autosnap-scheduler.service
[Unit]
Description=proxmox-autosnap scheduler tick

[Service]
Type=oneshot
WorkingDirectory=/opt/proxmox-autosnap/app
ExecStart=/usr/bin/python3 /opt/proxmox-autosnap/app/autosnap.py tick
EOF

cat <<EOF >/etc/systemd/system/autosnap-scheduler.timer
[Unit]
Description=proxmox-autosnap scheduler timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl enable -q --now autosnap-web.service
systemctl enable -q --now autosnap-scheduler.timer
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
