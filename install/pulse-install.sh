#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: rcourtman
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rcourtman/Pulse

# Import Functions and Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# --- Configuration ---
APP="Pulse"
APP_DIR="/opt/pulse-proxmox"
PULSE_USER="pulse"
SERVICE_NAME="pulse-monitor.service"
NODE_MAJOR_VERSION=20 # From install-pulse.sh
REPO_URL="https://github.com/rcourtman/Pulse.git"

# Create Pulse User
msg_info "Creating dedicated user '${PULSE_USER}'..."
if id "$PULSE_USER" &>/dev/null; then
  msg_warning "User '${PULSE_USER}' already exists. Skipping creation."
else
  useradd -r -m -d /opt/pulse-home -s /bin/bash "$PULSE_USER" # Give a shell for potential debugging/manual commands
  if useradd -r -m -d /opt/pulse-home -s /bin/bash "$PULSE_USER"; then
    msg_ok "User '${PULSE_USER}' created successfully."
  else
    msg_error "Failed to create user '${PULSE_USER}'."
    exit 1
  fi
fi

# Installing Dependencies
msg_info "Installing Dependencies (git, curl, sudo, gpg, jq, diffutils)..."
$STD apt-get install -y \
  git \
  curl \
  sudo \
  gpg \
  jq \
  diffutils
msg_ok "Installed Core Dependencies"

# Setup Node.js via NodeSource
msg_info "Setting up Node.js ${NODE_MAJOR_VERSION}.x repository..."
KEYRING_DIR="/usr/share/keyrings"
KEYRING_FILE="$KEYRING_DIR/nodesource.gpg"
mkdir -p "$KEYRING_DIR"
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --yes --dearmor -o "$KEYRING_FILE"
pipestatus=("${PIPESTATUS[@]}") # Capture pipestatus array
if [ "${pipestatus[1]}" -ne 0 ]; then
  msg_error "Failed to download NodeSource GPG key (gpg exited non-zero)."
  exit 1
fi
if [ "${pipestatus[0]}" -ne 0 ]; then msg_warning "Curl failed to download GPG key (curl exited non-zero), but gpg seemed okay? Proceeding cautiously."; fi
echo "deb [signed-by=$KEYRING_FILE] https://deb.nodesource.com/node_$NODE_MAJOR_VERSION.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list >/dev/null
msg_info "Updating package list after adding NodeSource..."
$STD apt-get update
msg_info "Installing Node.js ${NODE_MAJOR_VERSION}.x..."
$STD apt-get install -y nodejs
msg_ok "Installed Node.js"
msg_info "Node version: $(node -v)"
msg_info "npm version: $(npm -v)"

# Setup App
msg_info "Cloning ${APP} repository..."
# Clone as root initially, then change ownership
$STD git clone "$REPO_URL" "$APP_DIR"
cd "$APP_DIR" || {
  msg_error "Failed to cd into $APP_DIR"
  exit 1
}
msg_ok "Cloned ${APP} repository."

msg_info "Fetching latest release tag..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/rcourtman/Pulse/releases/latest | jq -r '.tag_name')
pipestatus=("${PIPESTATUS[@]}")
if [ "${pipestatus[0]}" -ne 0 ] || [ "${pipestatus[1]}" -ne 0 ] ||
  [[ -z "$LATEST_RELEASE" ]] || [[ "$LATEST_RELEASE" == "null" ]]; then
  msg_warning "Failed to fetch latest release tag. Proceeding with default branch."
  # Optionally, you could fetch tags via git and parse locally:
  # LATEST_RELEASE=$(git tag -l 'v*' --sort='-version:refname' | head -n 1)
  # if [[ -z "$LATEST_RELEASE" ]]; then msg_error "Could not find any release tags."; exit 1; fi
else
  msg_info "Checking out latest release tag: ${LATEST_RELEASE}"
  $STD git checkout "${LATEST_RELEASE}"
  msg_ok "Checked out ${LATEST_RELEASE}."
fi

# Install npm dependencies (as root because of /opt permissions)
msg_info "Installing Node.js dependencies for ${APP}..."
# Install root deps (includes dev for build)
$STD npm install --unsafe-perm
# Install server deps
cd server || {
  msg_error "Failed to cd into server directory."
  exit 1
}
$STD npm install --unsafe-perm
cd ..
msg_ok "Installed Node.js dependencies."

# Build CSS
msg_info "Building CSS assets..."
$STD npm run build:css
msg_ok "Built CSS assets."

# Configure Environment (.env)
msg_info "Configuring environment file..."
ENV_EXAMPLE="${APP_DIR}/.env.example"
ENV_FILE="${APP_DIR}/.env"
if [ -f "$ENV_EXAMPLE" ]; then
  # Copy example to .env if .env doesn't exist or is empty
  if [ ! -s "$ENV_FILE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    msg_info "Created ${ENV_FILE} from example."
    # Set default values (or leave placeholders for user to fill)
    # Using defaults similar to install-pulse.sh prompts
    sed -i 's|^PROXMOX_HOST=.*|PROXMOX_HOST=https://proxmox_host:8006|' "$ENV_FILE"
    sed -i 's|^PROXMOX_TOKEN_ID=.*|PROXMOX_TOKEN_ID=user@pam!tokenid|' "$ENV_FILE"
    sed -i 's|^PROXMOX_TOKEN_SECRET=.*|PROXMOX_TOKEN_SECRET=YOUR_API_SECRET_HERE|' "$ENV_FILE"
    sed -i 's|^PROXMOX_ALLOW_SELF_SIGNED_CERTS=.*|PROXMOX_ALLOW_SELF_SIGNED_CERTS=true|' "$ENV_FILE"
    sed -i 's|^PORT=.*|PORT=7655|' "$ENV_FILE"
    msg_warning "${ENV_FILE} created with placeholder values. Please edit it with your Proxmox details!"
  else
    msg_warning "${ENV_FILE} already exists. Skipping default configuration."
  fi
  # Set permissions on .env regardless
  chmod 600 "$ENV_FILE"
else
  msg_warning "${ENV_EXAMPLE} not found. Skipping environment configuration."
fi

# Set Permissions for the entire app directory
msg_info "Setting permissions for ${APP_DIR}..."
chown -R ${PULSE_USER}:${PULSE_USER} "${APP_DIR}"
# Ensure pulse user can write to logs if needed, and execute necessary files
find "${APP_DIR}" -type d -exec chmod 755 {} \;
find "${APP_DIR}" -type f -exec chmod 644 {} \;
# Make sure node_modules executables are runnable if needed (though npm scripts handle this)
# chmod +x ${APP_DIR}/server/server.js # Example if direct execution was needed
chmod 600 "$ENV_FILE" # Ensure .env is kept restricted
msg_ok "Set permissions."

# Save Installed Version
msg_info "Saving installed version information..."
VERSION_TO_SAVE="${LATEST_RELEASE:-$(git rev-parse --short HEAD)}" # Use tag or commit hash
echo "${VERSION_TO_SAVE}" >/opt/${APP}_version.txt
msg_ok "Saved version info (${VERSION_TO_SAVE})."

# Creating Service
msg_info "Creating systemd service for ${APP}..."
NODE_PATH=$(command -v node)
NPM_PATH=$(command -v npm)
cat <<EOF >/etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=${APP} Monitoring Application
After=network.target

[Service]
Type=simple
User=${PULSE_USER}
Group=${PULSE_USER}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
# Use absolute paths for node and npm
ExecStart=${NODE_PATH} ${NPM_PATH} run start
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ${SERVICE_NAME}
msg_ok "Created and enabled systemd service."

# Add motd and customize (standard functions)
motd_ssh
customize

# Cleanup
msg_info "Cleaning up apt cache..."
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned up."

# Sentinel file for ct script verification (optional but good practice)
touch /opt/pulse_install_complete
