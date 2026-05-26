#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: 9stannn
# License: MIT
# Source: https://github.com/IT-BAER/proxmorph


function header_info {
  clear
  cat <<"EOF"
  ____                __  __                  _     
 |  _ \ _ __ _____  _|  \/  | ___  _ __ _ __ | |__  
 | |_) | '__/ _ \ \/ / |\/| |/ _ \| '__| '_ \| '_ \ 
 |  __/| | | (_) >  <| |  | | (_) | |  | |_) | | | |
 |_|   |_|  \___/_/\_\_|  |_|\___/|_|  | .__/|_| |_|
                                       |_|          
EOF
}

if ! command -v curl &>/dev/null; then
  printf "\r\e[2K%b" '\033[93m Setup Source \033[m' >&2
  apt-get update >/dev/null 2>&1
  apt-get install -y curl >/dev/null 2>&1
fi
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/error_handler.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "proxmorph" "pve"

set -Eeuo pipefail
trap 'error_handler' ERR
load_functions

clear
header_info
ensure_usr_local_bin_persist
APP="ProxMorph"
PROXMORPH_DIR="/opt/proxmorph"

function uninstall() {
  msg_info "Uninstalling ${APP}"
  if [[ -f "$PROXMORPH_DIR/install.sh" ]]; then
    bash "$PROXMORPH_DIR/install.sh" uninstall >/dev/null 2>&1 || true
  else
    bash <(curl -fsSL https://raw.githubusercontent.com/IT-BAER/proxmorph/main/install.sh) uninstall >/dev/null 2>&1 || true
  fi
  rm -rf "$PROXMORPH_DIR"
  rm -f "/usr/local/bin/update_proxmorph"
  msg_ok "ProxMorph has been uninstalled"
  echo -e "${INFO} Please hard-refresh your browser (Ctrl+Shift+R) to see changes."
}

function update() {
  if [[ -f "$PROXMORPH_DIR/install.sh" ]]; then
    msg_info "Updating ${APP} via local repo"
    cd "$PROXMORPH_DIR" || exit
    git pull >/dev/null 2>&1
    bash "$PROXMORPH_DIR/install.sh" update
  else
    msg_info "Updating ${APP} via remote script"
    bash <(curl -fsSL https://raw.githubusercontent.com/IT-BAER/proxmorph/main/install.sh) update
  fi
  msg_ok "Updated successfully!"
  echo -e "${INFO} Please hard-refresh your browser (Ctrl+Shift+R) to apply the new themes."
  exit
}

function install() {
  msg_info "Preparing ${APP} installation"
  
  if ! command -v git &>/dev/null; then
    apt-get install -y git >/dev/null 2>&1
  fi
  
  if [[ ! -d "$PROXMORPH_DIR" ]]; then
    git clone https://github.com/IT-BAER/proxmorph.git "$PROXMORPH_DIR" >/dev/null 2>&1
  fi
  
  chmod +x "$PROXMORPH_DIR/install.sh"
  msg_ok "Repository cloned to $PROXMORPH_DIR"

  msg_info "Starting ${APP} installer"
  bash "$PROXMORPH_DIR/install.sh" install
  msg_ok "${APP} themes installed"

  # Create update script
  msg_info "Creating update script"
  ensure_usr_local_bin_persist
  cat <<'UPDATEEOF' >/usr/local/bin/update_proxmorph
#!/usr/bin/env bash
# ProxMorph Update Script
if [[ -f "/opt/proxmorph/install.sh" ]]; then
  cd /opt/proxmorph && git pull >/dev/null 2>&1
  bash /opt/proxmorph/install.sh update
else
  bash <(curl -fsSL https://raw.githubusercontent.com/IT-BAER/proxmorph/main/install.sh) update
fi
UPDATEEOF
  chmod +x /usr/local/bin/update_proxmorph
  msg_ok "Created update script (/usr/local/bin/update_proxmorph)"

  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO} Remember to hard-refresh your browser (Ctrl+Shift+R)!"
  echo -e "${INFO} Go to Profile Menu -> Color Theme to change it."
}

if [[ "${type:-}" == "update" ]]; then
  update
  exit 0
fi

if [[ -d "$PROXMORPH_DIR" ]]; then
  msg_warn "${APP} is already installed."
  echo ""

  echo -n "${TAB}Uninstall ${APP}? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    uninstall
    exit 0
  fi

  echo -n "${TAB}Update ${APP}? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
    update
    exit 0
  fi

  msg_warn "No action selected. Exiting."
  exit 0
fi

msg_warn "${APP} is not installed."
echo ""
echo -e "${TAB}${INFO} This will install:"
echo -e "${TAB}  - ${APP} Themes"
echo -e "${TAB}  - Custom Update Script"
echo ""

echo -n "${TAB}Install ${APP}? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi
