#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: JaredVititoe
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
    curl \
    sudo \
    mc \
    python3 \
    python3-pip \
    python3-venv \
    ffmpeg \
    libchromaprint-tools \
    imagemagick \
    mp3val \
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

msg_info "Creating Beets Configuration"
mkdir -p /var/lib/beets
mkdir -p /opt/beets/config

cat <<'EOF' >/opt/beets/config.yaml
# Beets Configuration
# Documentation: https://beets.readthedocs.io/

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

# Web plugin for UI access
web:
    host: 0.0.0.0
    port: 8337

# Chromaprint/AcoustID for fingerprinting
chroma:
    auto: yes

# Lyrics fetching
lyrics:
    auto: yes
    fallback: ''
    sources:
        - genius
        - lyricwiki
        - google

# Album art
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

# Genre from Last.fm
lastgenre:
    auto: yes
    source: album

# Clean metadata
scrub:
    auto: yes
EOF
msg_ok "Created Beets Configuration"

msg_info "Creating Shell Wrapper"
cat <<'EOF' >/usr/local/bin/beet
#!/bin/bash
source /opt/beets/venv/bin/activate
BEETSDIR=/opt/beets /opt/beets/venv/bin/beet "$@"
EOF
chmod +x /usr/local/bin/beet
msg_ok "Created Shell Wrapper"

msg_info "Creating Web Service (Optional)"
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
msg_ok "Created Web Service (disabled by default)"

msg_info "Setting Permissions"
chmod -R 755 /opt/beets
chmod -R 755 /var/lib/beets
msg_ok "Set Permissions"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
