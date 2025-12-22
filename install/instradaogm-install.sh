#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: rdeangel
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rdeangel/InstradaOGM

# 1. Setup error handling and source the standard install library
if ! command -v curl >/dev/null 2>&1; then
  apt update >/dev/null 2>&1
  apt install -y curl >/dev/null 2>&1
fi
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/install.func)

# 2. Application-specific setup
APP="InstradaOGM"
var_install="${APP,,}"
TAGS="firewall;management"

# 3. Default OPNsense Configuration
OPNSENSE_URL="https://192.168.1.1"
OPNSENSE_API_KEY="YOUR_API_KEY"
OPNSENSE_API_SECRET="YOUR_API_SECRET"

# 4. Define the Node.js installation function (using NVM)
setup_node() {
  msg_info "Installing NVM and Node.js 23"
  
  # Install dependencies
  $STD apt-get install -y curl build-essential
  
  # Install NVM (not through $STD because we need it in this shell)
  export NVM_DIR="$HOME/.nvm"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh -o /tmp/nvm-install.sh
  bash /tmp/nvm-install.sh >/dev/null 2>&1
  
  # Source NVM
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  
  # Install Node.js 23 (run directly, not through $STD)
  nvm install 23 >/dev/null 2>&1
  nvm use 23 >/dev/null 2>&1
  nvm alias default 23 >/dev/null 2>&1
  
  # Create symlinks to /usr/bin so systemd/pm2 can find node easily
  ln -sf "$NVM_DIR/versions/node/$(nvm current)/bin/node" /usr/bin/node
  ln -sf "$NVM_DIR/versions/node/$(nvm current)/bin/npm" /usr/bin/npm
  ln -sf "$NVM_DIR/versions/node/$(nvm current)/bin/npx" /usr/bin/npx
  
  msg_ok "Installed NVM and Node.js 23"
}

# 5. Define the InstradaOGM app setup function
setup_instrada() {
  msg_info "Downloading InstradaOGM Latest Release"
  $STD apt-get install -y git python3 sqlite3 ca-certificates mc jq rsync
  
  # Get latest release tag
  RELEASE=$(curl -fsSL https://api.github.com/repos/rdeangel/InstradaOGM/releases/latest | jq -r '.tag_name')
  
  # Download and extract release
  mkdir -p /opt/instrada-ogm
  cd /opt
  wget -q "https://github.com/rdeangel/InstradaOGM/archive/refs/tags/${RELEASE}.tar.gz"
  tar -xzf "${RELEASE}.tar.gz"
  rm "${RELEASE}.tar.gz"
  
  # Move extracted folder to correct location
  rm -rf /opt/instrada-ogm
  mv "InstradaOGM-${RELEASE#v}" /opt/instrada-ogm
  cd /opt/instrada-ogm
  
  # Save version info
  echo "${RELEASE}" > /opt/instrada-ogm/.version
  
  msg_ok "Downloaded InstradaOGM ${RELEASE}"
  
  msg_info "Configuring Database"
  $STD npm run db:switch:sqlite
  msg_ok "Configured Database"
  
  msg_info "Installing NPM Dependencies"
  $STD npm install
  msg_ok "Installed NPM Dependencies"
  
  msg_info "Generating Environment"
  # Configure Environment Variables
  NEXTAUTH_SECRET=$(openssl rand -base64 32)
  BACKUP_SECRET=$(openssl rand -hex 32)
  CONTAINER_IP=$(hostname -I | awk '{print $1}')
  
  cat > .env.production <<EOF
# --- Required OPNsense Configuration ---
OPNSENSE_URL=$OPNSENSE_URL
OPNSENSE_API_KEY=$OPNSENSE_API_KEY
OPNSENSE_API_SECRET=$OPNSENSE_API_SECRET
SKIP_SSL_VERIFICATION=false

# --- Database (SQLite) ---
DATABASE_URL="file:/opt/instrada-ogm/data/db/instrada-ogm.db"

# --- Security & Auth ---
NEXTAUTH_SECRET=$NEXTAUTH_SECRET
BACKUP_ENCRYPTION_SECRET_KEY=$BACKUP_SECRET
NEXTAUTH_URL="http://${CONTAINER_IP}:3000"
ALLOW_HTTP=true

# --- Application Settings ---
PORT=3000
NODE_ENV=production
APP_DEBUG_LEVEL=ERROR
DATA_FOLDER_PATH=data

# --- Local Credentials Login ---
AUTH_ALLOW_LOCAL_LOGIN=true
AUTH_REQUIRE_VERIFIED_EMAIL_LOCAL=false
AUTH_ALLOW_LOCAL_2FA=true
AUTH_PASSWORD_MIN_LENGTH=8

# --- Email Notifications (Optional) ---
AUTH_SMTP_HOST=smtp.example.com
AUTH_SMTP_PORT=25
AUTH_SMTP_USER=
AUTH_SMTP_PASS=
AUTH_SMTP_FROM_EMAIL=InstradaOGM<admin@example.com>
EOF
  ln -s .env.production .env
  msg_ok "Generated Environment"
}

# 6. Initialize Database
init_db() {
  msg_info "Initializing Database"
  $STD node scripts/setup-dirs.js
  $STD npm run db:init
  msg_ok "Initialized Database"
  
  msg_info "Seeding Database"
  bash -c "source /root/.bashrc && export NVM_DIR=/root/.nvm && source \$NVM_DIR/nvm.sh && cd /opt/instrada-ogm && export DATABASE_URL='file:/opt/instrada-ogm/data/db/instrada-ogm.db' && npx tsx prisma/seed.ts" >/dev/null 2>&1
  msg_ok "Seeded Database"
}

# 7. Build Application
build_app() {
  msg_info "Building Application"
  $STD npm run build
  msg_ok "Built Application"
}

# 8. Setup PM2
setup_pm2() {
  msg_info "Setting up PM2"
  $STD npm install -g pm2
  
  # Create symlink for pm2
  ln -sf "$(npm root -g)/pm2/bin/pm2" /usr/bin/pm2
  
  cd /opt/instrada-ogm
  pm2 start npm --name "instrada-ogm" -- start >/dev/null 2>&1
  $STD pm2 save
  $STD pm2 startup systemd -u root --hp /root
  
  msg_ok "Set up PM2"
}

# Run the functions in sequence
setting_up_container
network_check
update_os
setup_node
setup_instrada
init_db
build_app
setup_pm2
customize

msg_ok "Completed Successfully!"
echo -e "\n${INFO}${GN} Access: ${CL}${BL}http://$(hostname -I | awk '{print $1}'):3000${CL}"
echo -e "${INFO}${GN} Config: ${CL}Edit ${BL}/opt/instrada-ogm/.env.production${CL} for OPNsense API keys"
echo -e "${INFO}${GN} Restart: ${CL}Run ${BL}pm2 restart instrada-ogm${CL} after config changes\n"
