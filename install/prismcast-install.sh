#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: subsistence
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/hjdhjd/prismcast

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_hwaccel

# Installed before the apt packages below: Debian's "novnc" package depends on
# Debian's own nodejs, and installing nodesource's Node.js afterward replaces
# that package, which apt then removes as an orphaned dependency - taking novnc
# down with it. Installing Node.js first means novnc's dependency is already
# satisfied by the nodesource package and nothing gets removed later.
NODE_VERSION="22" setup_nodejs

msg_info "Installing Xvfb/VNC Dependencies"
$STD apt install -y \
  xvfb \
  x11vnc \
  x11-xkb-utils \
  xfonts-100dpi \
  xfonts-75dpi \
  xfonts-scalable \
  x11-apps \
  xauth \
  novnc \
  websockify \
  fonts-liberation
msg_ok "Installed Xvfb/VNC Dependencies"

msg_info "Installing Chrome Dependencies"
$STD apt install -y \
  libasound2t64 \
  libatk1.0-0 \
  libatk-bridge2.0-0 \
  libcairo2 \
  libcups2 \
  libdbus-1-3 \
  libdrm2 \
  libexpat1 \
  libfontconfig1 \
  libgbm1 \
  libgdk-pixbuf-2.0-0 \
  libglib2.0-0 \
  libgtk-3-0 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libpangocairo-1.0-0 \
  libstdc++6 \
  libx11-6 \
  libx11-xcb1 \
  libxcb1 \
  libxcomposite1 \
  libxcursor1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxi6 \
  libxkbcommon0 \
  libxrandr2 \
  libxrender1 \
  libxss1 \
  libxtst6 \
  lsb-release \
  xdg-utils
msg_ok "Installed Chrome Dependencies"

msg_info "Adding Google Chrome APT Repository"
setup_deb822_repo "google-chrome" "https://dl.google.com/linux/linux_signing_key.pub" "http://dl.google.com/linux/chrome/deb/" "stable" "main" "amd64"
msg_ok "Added Google Chrome APT Repository"

msg_info "Installing Google Chrome"
$STD apt install -y google-chrome-stable
msg_ok "Installed Google Chrome"

msg_info "Creating Chrome Sandbox Wrapper"
# --use-gl=angle --use-angle=gl-egl gets Chrome real GPU-backed rendering via direct EGL/GBM access to
# the DRM device, bypassing the fact that stock Debian's Xvfb has no DRI3 device backing of its own.
# The spoofed --user-agent is load-bearing, not cosmetic: Xfinity Stream's guide page checks the client
# OS and hard-blocks Linux ("Update your browser to start streaming"/"unsupported operating system"),
# which otherwise makes every channel fail with "guide page did not load within timeout" regardless of
# login state. Since every Docker/LXC deployment of this app runs on Linux, without this override the
# Xfinity integration - the app's primary use case - does not work at all.
CHROME_VERSION=$(google-chrome-stable --version | grep -oP '[\d.]+' | head -1)
cat <<EOF >/usr/local/bin/chrome-no-sandbox
#!/bin/bash
exec /usr/bin/google-chrome-stable --no-sandbox --disable-setuid-sandbox --disable-gpu-sandbox \\
  --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,AcceleratedVideoEncoder,VaapiIgnoreDriverChecks \\
  --ignore-gpu-blocklist --use-gl=angle --use-angle=gl-egl \\
  --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${CHROME_VERSION} Safari/537.36" "\$@"
EOF
chmod +x /usr/local/bin/chrome-no-sandbox
msg_ok "Created Chrome Sandbox Wrapper"

fetch_and_deploy_gh_release "prismcast" "hjdhjd/prismcast" "tarball"

msg_info "Building PrismCast"
cd /opt/prismcast
export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
$STD npm ci
$STD npm run build
mkdir -p /opt/prismcast_data
msg_ok "Built PrismCast"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/xvfb.service
[Unit]
Description=Virtual Framebuffer X Server for PrismCast
After=network.target

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'rm -f /tmp/.X99-lock'
ExecStart=/usr/bin/Xvfb :99 -screen 0 1920x1080x24 -dpi 96 +extension COMPOSITE +extension DAMAGE +extension GLX +extension RANDR +extension RENDER +extension MIT-SHM +extension XFIXES +extension XTEST -nolisten tcp -ac -noreset
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/x11vnc.service
[Unit]
Description=x11vnc Server for PrismCast
After=xvfb.service
Requires=xvfb.service

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -display :99 -forever -shared -nopw -rfbport 5900 -quiet
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/novnc.service
[Unit]
Description=noVNC WebSocket Proxy for PrismCast
After=x11vnc.service
Requires=x11vnc.service

[Service]
Type=simple
ExecStart=/usr/bin/websockify --web=/usr/share/novnc 6080 localhost:5900
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/prismcast.service
[Unit]
Description=PrismCast
After=network-online.target xvfb.service
Wants=network-online.target
Requires=xvfb.service

[Service]
Type=simple
User=root
Environment=DISPLAY=:99
Environment=CHROME_BIN=/usr/local/bin/chrome-no-sandbox
Environment=PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
Environment=PRISMCAST_DATA_DIR=/opt/prismcast_data
WorkingDirectory=/opt/prismcast
ExecStart=/usr/bin/node /opt/prismcast/dist/index.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Services"

msg_info "Starting Services"
systemctl enable -q --now xvfb
sleep 2
systemctl enable -q --now x11vnc
sleep 1
systemctl enable -q --now novnc
sleep 1
systemctl enable -q --now prismcast
msg_ok "Started Services"

motd_ssh
cat <<'EOF' >/etc/profile.d/01-prismcast-urls.sh
_pc_ip=$(ip -4 route get 1 2>/dev/null | sed -n 's/.* src \([0-9.]\+\).*/\1/p' | head -1)
echo " PrismCast tuner (add manually in Plex as ${_pc_ip}:5004): http://${_pc_ip}:5004/discover.json"
echo " PrismCast web interface: http://${_pc_ip}:5589"
echo " Chrome direct VNC: vnc://${_pc_ip}:5900"
echo " Chrome noVNC (recommended): http://${_pc_ip}:6080/vnc.html"
echo ""
unset _pc_ip
EOF
chmod +x /etc/profile.d/01-prismcast-urls.sh
customize
cleanup_lxc
