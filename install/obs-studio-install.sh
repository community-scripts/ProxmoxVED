#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://obsproject.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_hwaccel

msg_info "Installing OBS Studio and Desktop Environment"
$STD apt install -y \
  obs-studio \
  xvfb \
  openbox \
  x11vnc \
  lxterminal \
  dbus \
  pulseaudio \
  fonts-dejavu-core
msg_ok "Installed OBS Studio and Desktop Environment"

msg_info "Configuring VNC password"
mkdir -p /root/.vnc
echo "obsstudio" | x11vnc -storepasswd /root/.vnc/passwd >/dev/null 2>&1
msg_ok "VNC password set (default: obsstudio)"

msg_info "Creating startup script"
cat <<'EOF' >/usr/local/bin/obs-desktop.sh
#!/bin/bash
export DISPLAY=:1
Xvfb :1 -screen 0 1920x1080x24 +extension GLX &
sleep 2
openbox &
sleep 1
x11vnc -display :1 -rfbauth /root/.vnc/passwd -forever -shared -rfbport 5901
EOF
chmod +x /usr/local/bin/obs-desktop.sh
msg_ok "Created startup script"

msg_info "Creating systemd service"
cat <<'EOF' >/etc/systemd/system/obs-desktop.service
[Unit]
Description=OBS Studio Desktop (Xvfb + Openbox + x11vnc)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/obs-desktop.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q obs-desktop.service
msg_ok "Created systemd service"

msg_info "Verifying VAAPI tools"
if command -v vainfo &>/dev/null; then
  msg_ok "vainfo installed — run manually after container restart to verify QuickSync"
else
  msg_warn "vainfo not found — hardware acceleration may not be configured"
fi

if command -v v4l2-ctl &>/dev/null; then
  msg_ok "v4l2-ctl installed for capture device diagnostics"
fi

motd_ssh
customize
cleanup_lxc
