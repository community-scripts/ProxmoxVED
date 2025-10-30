#!/usr/bin/env bash

# Couleurs pour les messages
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

# Installation des dépendances système
msg_info "Updating system packages"
apt-get update &>/dev/null
apt-get upgrade -y &>/dev/null
msg_ok "Updated system packages"

msg_info "Installing dependencies"
apt-get install -y curl sudo git wget postgresql postgresql-contrib &>/dev/null
msg_ok "Installed dependencies"

# Installation de Node.js 20
msg_info "Installing Node.js"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &>/dev/null
apt-get install -y nodejs &>/dev/null
msg_ok "Installed Node.js $(node --version)"

# Configuration de PostgreSQL
msg_info "Configuring PostgreSQL"
systemctl enable --now postgresql &>/dev/null
sudo -u postgres psql -c "CREATE DATABASE snowshare;" &>/dev/null
sudo -u postgres psql -c "CREATE USER snowshare WITH ENCRYPTED PASSWORD 'snowshare';" &>/dev/null
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE snowshare TO snowshare;" &>/dev/null
sudo -u postgres psql -c "ALTER DATABASE snowshare OWNER TO snowshare;" &>/dev/null
msg_ok "Configured PostgreSQL"

# Clonage du dépôt
msg_info "Cloning SnowShare repository"
git clone https://github.com/TuroYT/snowshare.git /opt/snowshare &>/dev/null
cd /opt/snowshare
msg_ok "Cloned repository"

# Installation des dépendances NPM
msg_info "Installing NPM dependencies"
npm ci &>/dev/null
msg_ok "Installed NPM dependencies"

# Configuration de l'environnement
msg_info "Configuring environment"
cat <<EOF > /opt/snowshare/.env
DATABASE_URL="postgresql://snowshare:snowshare@localhost:5432/snowshare"
NEXTAUTH_URL="http://localhost:3000"
NEXTAUTH_SECRET="$(openssl rand -base64 32)"
ALLOW_SIGNUP=true
NODE_ENV=production
EOF
msg_ok "Configured environment"

# Génération Prisma et migrations
msg_info "Running Prisma migrations"
npx prisma generate &>/dev/null
npx prisma migrate deploy &>/dev/null
msg_ok "Ran Prisma migrations"

# Build de l'application
msg_info "Building SnowShare"
npm run build &>/dev/null
msg_ok "Built SnowShare"

# Création du service systemd
msg_info "Creating systemd service"
cat <<EOF >/etc/systemd/system/snowshare.service
[Unit]
Description=SnowShare - Modern File Sharing Platform
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/snowshare
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now snowshare.service &>/dev/null
msg_ok "Created systemd service"

# Configuration du cron pour le nettoyage
msg_info "Setting up cleanup cron job"
(crontab -l 2>/dev/null; echo "0 2 * * * cd /opt/snowshare && /usr/bin/npm run cleanup:expired >> /var/log/snowshare-cleanup.log 2>&1") | crontab -
msg_ok "Setup cleanup cron job"

# Nettoyage
msg_info "Cleaning up"
apt-get autoremove -y &>/dev/null
apt-get autoclean -y &>/dev/null
msg_ok "Cleaned up"