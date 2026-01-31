#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: JaredVititoe (JaredVititoe)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://beets.io/

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
  python3-pip \
  python3-venv \
  ffmpeg \
  libchromaprint-tools \
  imagemagick \
  flac
msg_ok "Installed Dependencies"

msg_info "Setting up Beets"
mkdir -p /opt/beets
python3 -m venv /opt/beets/venv
source /opt/beets/venv/bin/activate
$STD pip install --upgrade pip
$STD pip install beets pyacoustid pylast requests beautifulsoup4 flask
deactivate
msg_ok "Set up Beets"

msg_info "Creating Configuration"
mkdir -p /var/lib/beets
cat <<'EOF' >/opt/beets/config.yaml
directory: /media/music
library: /var/lib/beets/library.db

import:
  move: no
  copy: yes
  write: yes
  log: /var/lib/beets/import.log

paths:
  default: $albumartist/$album%aunique{}/$track - $title
  singleton: Singles/$artist - $title
  comp: Compilations/$album%aunique{}/$track - $title

plugins:
  - chroma
  - lyrics
  - fetchart
  - embedart
  - lastgenre
  - scrub
  - duplicates
  - missing
  - info
  - edit
  - web

web:
  host: 0.0.0.0
  port: 8337

chroma:
  auto: yes

lyrics:
  auto: yes
  fallback: ''
  sources:
    - genius
    - google

fetchart:
  auto: yes
  sources:
    - filesystem
    - coverart
    - itunes
    - amazon
    - albumart

embedart:
  auto: yes
  remove_art_file: no

lastgenre:
  auto: yes
  source: album

scrub:
  auto: yes
EOF
msg_ok "Created Configuration"

msg_info "Creating Shell Wrapper"
cat <<'EOF' >/usr/local/bin/beet
#!/bin/bash
source /opt/beets/venv/bin/activate
BEETSDIR=/opt/beets /opt/beets/venv/bin/beet "$@"
EOF
chmod +x /usr/local/bin/beet
msg_ok "Created Shell Wrapper"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/beets-web.service
[Unit]
Description=Beets Web Interface
After=network.target

[Service]
Type=simple
Environment="BEETSDIR=/opt/beets"
ExecStart=/opt/beets/venv/bin/beet web
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now beets-web
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
