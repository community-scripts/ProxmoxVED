#!/usr/bin/env bash
set -euo pipefail

# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/pewdiepie-archdaemon/odysseus

if [[ -n "${FUNCTIONS_FILE_PATH:-}" ]]; then
  source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
  HAS_COMMUNITY_FUNCS=true
else
  HAS_COMMUNITY_FUNCS=false
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  NC='\033[0m'
  STD() { "$@" >/dev/null 2>&1; }
  msg_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
  msg_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
  msg_error() { echo -e "[ERROR] $1"; }
  setting_up_container() { :; }
  network_check() { :; }
  update_os() {
    msg_info "Updating Container OS"
    apt-get update -qq
    apt-get -o Dpkg::Options::="--force-confold" -y dist-upgrade -qq
    msg_ok "Updated Container OS"
  }
  motd_ssh() {
    grep -qxF "export TERM='xterm-256color'" /root/.bashrc || echo "export TERM='xterm-256color'" >>/root/.bashrc
    OS_NAME=$(grep ^NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    OS_VERSION=$(grep ^VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '"')
    PROFILE_FILE="/etc/profile.d/00_lxc-details.sh"
    cat <<EOF >"$PROFILE_FILE"
echo -e ""
echo -e "\033[1mOdysseus LXC Container\033[0m"
echo -e "  Provided by: \033[32mcommunity-scripts ORG\033[0m | GitHub: \033[32mhttps://github.com/community-scripts/ProxmoxVE\033[0m"
echo ""
echo -e "  OS: \033[32m${OS_NAME} - Version: ${OS_VERSION}\033[0m"
echo -e "  Hostname: \033[32m\$(hostname)\033[0m"
echo -e "  IP Address: \033[32m\$(hostname -I | awk '{print \$1}')\033[0m"
echo -e "  Web UI: \033[32mhttp://\$(hostname -I | awk '{print \$1}'):7000\033[0m"
echo -e "  Credentials: \033[32m~/odysseus.creds\033[0m"
echo -e "  Update: \033[32mupdate\033[0m"
echo ""
EOF
    chmod -x /etc/update-motd.d/* 2>/dev/null || true
  }
  customize() {
    GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
    mkdir -p "$(dirname "$GETTY_OVERRIDE")"
    cat <<EOF >"$GETTY_OVERRIDE"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
    systemctl daemon-reload
    cat <<'UPDATE_SCRIPT' >/usr/bin/update
#!/bin/bash
cd /opt/odysseus
git pull
/opt/odysseus/.venv/bin/pip install -r requirements.txt
systemctl restart odysseus
echo "Odysseus updated successfully!"
UPDATE_SCRIPT
    chmod +x /usr/bin/update
  }
  cleanup_lxc() {
    msg_info "Cleaning up"
    apt-get -y autoremove -qq
    apt-get -y autoclean -qq
    msg_ok "Cleaned up"
  }
  setup_uv() {
    msg_info "Installing uv"
    curl -fsSL https://astral.sh/uv/install.sh | sh
    export PATH="/root/.local/bin:$PATH"
    if [[ -n "${PYTHON_VERSION:-}" ]]; then
      uv python install "$PYTHON_VERSION"
    fi
    msg_ok "Installed uv"
  }
  verb_ip6() { :; }
  catch_errors() { set -euo pipefail; }
fi

color() { :; }
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
STD apt-get install -y \
  build-essential \
  cmake \
  curl \
  git \
  nodejs \
  npm \
  tmux \
  openssh-client \
  python3-dev
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv
export PATH="/root/.local/bin:/usr/local/bin:$PATH"

msg_info "Cloning Odysseus"
STD git clone https://github.com/pewdiepie-archdaemon/odysseus.git /opt/odysseus
msg_ok "Cloned Odysseus"

msg_info "Setting Up Virtual Environment"
cd /opt/odysseus
STD uv venv /opt/odysseus/.venv --python 3.12
STD uv pip install -r /opt/odysseus/requirements.txt --python /opt/odysseus/.venv/bin/python3
msg_ok "Set Up Virtual Environment"

msg_info "Installing ChromaDB"
STD uv pip install chromadb --python /opt/odysseus/.venv/bin/python3
msg_ok "Installed ChromaDB"

msg_info "Installing ntfy"
NTFY_VERSION=$(curl -fsSL https://api.github.com/repos/binwiederhier/ntfy/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')
curl -fsSL "https://github.com/binwiederhier/ntfy/releases/download/v${NTFY_VERSION}/ntfy_${NTFY_VERSION}_linux_amd64.tar.gz" | tar xz -C /tmp
STD install -m 755 /tmp/ntfy_${NTFY_VERSION}_linux_amd64/ntfy /usr/local/bin/ntfy
rm -rf /tmp/ntfy_${NTFY_VERSION}_linux_amd64
msg_ok "Installed ntfy"

msg_info "Creating Data Directories"
mkdir -p /opt/odysseus/data /opt/odysseus/logs /opt/odysseus/data/chroma
msg_ok "Created Data Directories"

msg_info "Generating Admin Credentials"
ADMIN_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)
{
  echo "Odysseus Credentials"
  echo "Admin User: admin"
  echo "Admin Password: $ADMIN_PASS"
} >>~/odysseus.creds
msg_ok "Generated Admin Credentials"

msg_info "Creating ChromaDB Service"
cat <<EOF >/etc/systemd/system/chromadb.service
[Unit]
Description=ChromaDB Vector Store
After=network.target

[Service]
Type=simple
ExecStart=/opt/odysseus/.venv/bin/chroma run --host 127.0.0.1 --port 8000 --path /opt/odysseus/data/chroma
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created ChromaDB Service"

msg_info "Creating ntfy Service"
cat <<EOF >/etc/systemd/system/ntfy.service
[Unit]
Description=ntfy Notification Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ntfy serve --listen-http :8091
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created ntfy Service"

msg_info "Creating Odysseus Service"
cat <<EOF >/etc/systemd/system/odysseus.service
[Unit]
Description=Odysseus AI Workspace
After=network.target chromadb.service
Requires=chromadb.service

[Service]
Type=simple
WorkingDirectory=/opt/odysseus
Environment=PATH=/opt/odysseus/.venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=ODYSSEUS_ADMIN_PASSWORD=$ADMIN_PASS
Environment=AUTH_ENABLED=true
Environment=CHROMADB_HOST=127.0.0.1
Environment=CHROMADB_PORT=8000
Environment=SEARXNG_INSTANCE=
ExecStart=/opt/odysseus/.venv/bin/python3 -m uvicorn app:app --host 0.0.0.0 --port 7000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Odysseus Service"

msg_info "Running Odysseus Setup"
cd /opt/odysseus
ODYSSEUS_ADMIN_PASSWORD="$ADMIN_PASS" STD /opt/odysseus/.venv/bin/python3 setup.py
msg_ok "Ran Odysseus Setup"

msg_info "Enabling and Starting Services"
STD systemctl daemon-reload
STD systemctl enable -q --now chromadb ntfy odysseus
msg_ok "Enabled and Started Services"

motd_ssh
customize
cleanup_lxc
