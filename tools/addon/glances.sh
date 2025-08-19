#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)

APP="Glances"
IP=$(hostname -I | awk '{print $1}')
hostname="$(hostname)"

header_info "$APP"
catch_errors

# install on Debian/Ubuntu
install_glances_debian() {
  msg_info "Installing dependencies"
  $STD apt-get update
  $STD apt-get install -y gcc lm-sensors wireless-tools
  msg_ok "Installed dependencies"

  msg_info "Setting up Python + uv"
  setup_uv PYTHON_VERSION="3.12"
  msg_ok "Setup Python + uv"

  msg_info "Installing $APP (with web UI)"
  cd /opt
  mkdir -p glances
  cd glances
  uv venv
  source .venv/bin/activate
  uv pip install --upgrade pip wheel setuptools
  uv pip install "glances[web]"
  deactivate
  msg_ok "Installed $APP"

  msg_info "Creating systemd service"
  cat <<EOF >/etc/systemd/system/glances.service
[Unit]
Description=Glances - An eye on your system
After=network.target

[Service]
Type=simple
ExecStart=/opt/glances/.venv/bin/glances -w
Restart=on-failure
WorkingDirectory=/opt/glances

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now glances
  msg_ok "Created systemd service"

  echo -e "\n$APP is now running at: http://$IP:61208\n"
}

# uninstall on Debian/Ubuntu
uninstall_glances_debian() {
  msg_info "Uninstalling $APP"
  systemctl disable -q --now glances || true
  rm -f /etc/systemd/system/glances.service
  rm -rf /opt/glances
  msg_ok "Removed $APP"
}

# install on Alpine
install_glances_alpine() {
  msg_info "Installing dependencies"
  $STD apk update
  $STD apk add --no-cache gcc musl-dev python3 py3-pip py3-virtualenv lm-sensors wireless-tools
  msg_ok "Installed dependencies"

  msg_info "Setting up Python + uv"
  setup_uv PYTHON_VERSION="3.12"
  msg_ok "Setup Python + uv"

  msg_info "Installing $APP (with web UI)"
  cd /opt
  mkdir -p glances
  cd glances
  uv venv
  source .venv/bin/activate
  uv pip install --upgrade pip wheel setuptools
  uv pip install "glances[web]"
  deactivate
  msg_ok "Installed $APP"

  msg_info "Creating OpenRC service"
  cat <<'EOF' >/etc/init.d/glances
#!/sbin/openrc-run
command="/opt/glances/.venv/bin/glances"
command_args="-w"
command_background="yes"
pidfile="/run/glances.pid"
name="glances"
description="Glances monitoring tool"
EOF
  chmod +x /etc/init.d/glances
  rc-update add glances default
  rc-service glances start
  msg_ok "Created OpenRC service"

  echo -e "\n$APP is now running at: http://$IP:61208\n"
}

# uninstall on Alpine
uninstall_glances_alpine() {
  msg_info "Uninstalling $APP"
  rc-service glances stop || true
  rc-update del glances || true
  rm -f /etc/init.d/glances
  rm -rf /opt/glances
  msg_ok "Removed $APP"
}

# options menu
OPTIONS=(Install "Install $APP"
  Uninstall "Uninstall $APP")

CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "$APP" --menu "Select an option:" 10 58 2 \
  "${OPTIONS[@]}" 3>&1 1>&2 2>&3 || true)

# OS detection
if grep -qi "alpine" /etc/os-release; then
  case "$CHOICE" in
  Install) install_glances_alpine ;;
  Uninstall) uninstall_glances_alpine ;;
  *) exit 0 ;;
  esac
else
  case "$CHOICE" in
  Install) install_glances_debian ;;
  Uninstall) uninstall_glances_debian ;;
  *) exit 0 ;;
  esac
fi
