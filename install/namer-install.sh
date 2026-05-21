#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nanja-at-web
# Co-Author: OpenAI Codex
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Nanja-at-web/namer

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP_PIP_SPEC="${NAMER_PIP_SPEC:-git+https://github.com/Nanja-at-web/namer.git@codex/proxmox-setup-wizard}"

msg_info "Installing Dependencies"
$STD apt install -y \
  ffmpeg \
  git \
  nfs-common
msg_ok "Installed Dependencies"

UV_PYTHON="3.11" setup_uv

msg_info "Setting up Application"
install -d -m 755 \
  /opt/namer \
  /etc/namer \
  /mnt/nas \
  /var/lib/namer/watch \
  /var/lib/namer/work \
  /var/lib/namer/failed \
  /var/lib/namer/dest \
  /var/lib/namer/database
cd /opt/namer
$STD uv venv --clear --python 3.11 /opt/namer/.venv
$STD uv pip install --python /opt/namer/.venv/bin/python --upgrade "${APP_PIP_SPEC}"
msg_ok "Set up Application"

if [[ ! -f /etc/namer/namer.cfg ]]; then
  msg_info "Creating Bootstrap Config"
  /opt/namer/.venv/bin/python - <<'PY'
from configupdater import ConfigUpdater
from importlib import resources
from pathlib import Path

config_path = Path("/etc/namer/namer.cfg")
config_text = resources.files("namer").joinpath("namer.cfg.default").read_text(encoding="utf-8")
updater = ConfigUpdater(allow_no_value=True)
updater.read_string(config_text)

updater["namer"]["porndb_token"].value = ""
updater["namer"]["database_path"].value = "/var/lib/namer/database"

updater["setup"]["is_setup_complete"].value = "False"
updater["setup"]["setup_mode"].value = "wizard"
updater["setup"]["storage_mode"].value = "nfs"
updater["setup"]["nas_host"].value = ""
updater["setup"]["nas_share"].value = ""
updater["setup"]["nas_mount_path"].value = "/mnt/nas"
updater["setup"]["nas_mount_options"].value = "defaults,_netdev"

updater["watchdog"]["watch_dir"].value = "/var/lib/namer/watch"
updater["watchdog"]["work_dir"].value = "/var/lib/namer/work"
updater["watchdog"]["failed_dir"].value = "/var/lib/namer/failed"
updater["watchdog"]["dest_dir"].value = "/var/lib/namer/dest"
updater["watchdog"]["web"].value = "True"

config_path.write_text(str(updater), encoding="utf-8")
PY
  chmod 0640 /etc/namer/namer.cfg
  msg_ok "Created Bootstrap Config"
fi

msg_info "Creating Environment File"
cat <<EOF >/etc/default/namer
NAMER_CONFIG=/etc/namer/namer.cfg
EOF
msg_ok "Created Environment File"

msg_info "Creating Service"
SERVICE_EXISTS="no"
if [[ -f /etc/systemd/system/namer-watchdog.service ]]; then
  SERVICE_EXISTS="yes"
fi
cat <<EOF >/etc/systemd/system/namer-watchdog.service
[Unit]
Description=Namer watchdog
After=network-online.target remote-fs.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/namer
EnvironmentFile=/etc/default/namer
ExecStart=/opt/namer/.venv/bin/python -m namer watchdog
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
if [[ "${SERVICE_EXISTS}" == "yes" ]]; then
  systemctl daemon-reload
fi
systemctl enable -q --now namer-watchdog
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
