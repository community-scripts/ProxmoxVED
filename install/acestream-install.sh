#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: jamezrin
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://acestream.media/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# AceStream Configuration Variables
ACESTREAM_VERSION="3.2.3"
ACESTREAM_OS="ubuntu_22.04"
ACESTREAM_ARCH="x86_64"
ACESTREAM_PYTHON="py3.10"
ACESTREAM_BASE_URL="https://download.acestream.media/linux"
ACESTREAM_FILENAME="acestream_${ACESTREAM_VERSION}_${ACESTREAM_OS}_${ACESTREAM_ARCH}_${ACESTREAM_PYTHON}.tar.gz"
ACESTREAM_URL="${ACESTREAM_BASE_URL}/${ACESTREAM_FILENAME}"

msg_info "Installing Dependencies"
$STD apt-get install -y \
  wget \
  curl \
  python3 \
  python3-pip \
  python3-venv \
  libpython3.10 \
  python-setuptools \
  python3-m2crypto \
  python3-apsw \
  libvlc-dev \
  vlc-plugin-base \
  ffmpeg
msg_ok "Installed Dependencies"

msg_info "Creating AceStream User"
useradd -r -s /bin/false -d /var/lib/acestream -m acestream
msg_ok "Created AceStream User"

msg_info "Downloading and Installing AceStream"
mkdir -p /opt/acestream
cd /tmp || exit
$STD wget -O acestream.tar.gz "$ACESTREAM_URL"
$STD tar -xf acestream.tar.gz -C /opt/acestream
rm -f acestream.tar.gz

# Install python requirements
msg_info "Installing Python requirements"
$STD python3.10 -m pip install --upgrade pip
$STD python3.10 -m pip install -r /opt/acestream/requirements.txt
msg_ok "Installed Python requirements"

# Create symlinks for FFmpeg libraries
msg_info "Creating library symlinks"
pushd /opt/acestream/lib || exit

_libsymlinks() {
  local lib="$1" major="$2" version="$3"
  if [ -f "lib${lib}.so.${major}.${version}" ]; then
    ln -sf "lib${lib}.so.${major}.${version}" "lib${lib}.so"
    ln -sf "lib${lib}.so.${major}.${version}" "lib${lib}.so.${major}"
  fi
}

_libsymlinks "avcodec"   "58" "100.100"
_libsymlinks "avdevice"  "58" "11.101"
_libsymlinks "avfilter"   "7" "87.100"
_libsymlinks "avformat"  "58" "51.100"
_libsymlinks "avutil"    "56" "58.100"
_libsymlinks "fdk-aac"    "2" "0.1"
_libsymlinks "mp3lame"    "0" "0.0"
_libsymlinks "swresample" "3" "8.100"
_libsymlinks "swscale"    "5" "8.100"

# Special symlink for x264
if [ -f "libx264.so.148" ]; then
    ln -sf "libx264.so.148" "libx264.so"
fi

popd || exit
msg_ok "Created library symlinks"

# Set ownership to acestream user
chown -R acestream:acestream /opt/acestream

# Make the AceStream engine executable
if [ -f /opt/acestream/acestreamengine ]; then
    chmod +x /opt/acestream/acestreamengine
else
    msg_error "AceStream engine executable not found!"
    exit 1
fi

# Make the start-engine script executable and update its ROOT path
if [ -f /opt/acestream/start-engine ]; then
    chmod +x /opt/acestream/start-engine
    # Update the ROOT path in start-engine script
    sed -i 's|^ROOT=.*|ROOT=/opt/acestream|' /opt/acestream/start-engine
fi
msg_ok "Installed AceStream"

msg_info "Creating AceStream Configuration Directory"
mkdir -p /var/lib/acestream
chown -R acestream:acestream /var/lib/acestream
msg_ok "Created Configuration Directory"

msg_info "Creating AceStream Logs Directory"
mkdir -p /var/log/acestream
chown -R acestream:acestream /var/log/acestream
msg_ok "Created Logs Directory"

msg_info "Creating SystemD Service"
cat <<EOF >/etc/systemd/system/acestream.service
[Unit]
Description=AceStream Engine Service
After=network.target

[Service]
Type=simple
User=acestream
Group=acestream
WorkingDirectory=/opt/acestream
Environment=LD_LIBRARY_PATH=/opt/acestream/lib
ExecStart=/opt/acestream/start-engine --client-console --http-host 0.0.0.0 --live-cache-type memory --vod-cache-type memory --state-dir /var/lib/acestream --log-file /var/log/acestream/acestream-engine.log
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now acestream
msg_ok "Created SystemD Service"

# Create convenient symlinks for command-line usage
msg_info "Creating convenience symlinks"
ln -sf /opt/acestream/start-engine /usr/local/bin/acestream-engine
ln -sf /opt/acestream/acestreamengine /usr/local/bin/acestreamengine
msg_ok "Created convenience symlinks"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
