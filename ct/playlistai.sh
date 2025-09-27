#!/usr/bin/env bash
# PlaylistAI LXC Container Script
# Author: Michael (Hoosier-IT)
# License: MIT

# Source the community-scripts build functions (patched to your fork/branch for testing)
source <(curl -fsSL https://raw.githubusercontent.com/Hoosier-IT/ProxmoxVED/playlistai/misc/build.func)

APP="PlaylistAI"
var_os="debian"
var_version="12"
var_cpu="2"
var_ram="1024"
var_disk="4"
var_unprivileged="1"
var_tags="music;llm;flask"
var_hostname="playlistai"

header_info "$APP"
variables
color
catch_errors

function description() {
  echo -e "PlaylistAI: Flask API that curates playlists using Music Assistant and an LLM."
  echo -e "Supports both standalone Music Assistant (REST) and the HA add-on (WebSocket) via music-assistant-client."
}

# ✅ Corrected update_script to run installer inside the container
function update_script() {
  header_info
  msg_info "Running PlaylistAI installation inside container $CTID"

  pct exec "$CTID" -- bash -c "curl -fsSL https://raw.githubusercontent.com/Hoosier-IT/ProxmoxVED/playlistai/install/playlistai-install.sh | bash"

  msg_ok "PlaylistAI installation complete"
}

start
build_container
description
msg_ok "Completed Successfully!"
