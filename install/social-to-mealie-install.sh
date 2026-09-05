#!/usr/bin/env bash

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl wget git unzip ffmpeg python3 python3-pip ca-certificates
msg_ok "Installed Dependencies"

msg_info "Installing gallery-dl"
$STD apt-get install -y gallery-dl
msg_ok "Installed gallery-dl"

NODE_MODULE="pnpm@latest" NODE_VERSION="22" setup_nodejs

msg_info "Cloning Social Media to Mealie Repository"
git clone https://github.com/GerardPolloRebozado/social-to-mealie.git /opt/social-to-mealie &>/dev/null
cd /opt/social-to-mealie
msg_ok "Cloned Repository"

msg_info "Downloading local yt-dlp"
wget -q -O ./yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
chmod +x ./yt-dlp
msg_ok "Downloaded yt-dlp"

msg_info "Installing Node Dependencies"
$STD pnpm install --frozen-lockfile
msg_ok "Installed Node Dependencies"

msg_info "Building Application"
export NEXT_TELEMETRY_DISABLED=1
$STD pnpm run build
msg_ok "Built Application"

msg_info "Creating Systemd Service"
cp example.env .env
sed -i 's|LOCAL_TRANSCRIPTION_MODEL=.*|LOCAL_TRANSCRIPTION_MODEL=Xenova/whisper-tiny|g' .env

cat <<EOF >/etc/systemd/system/social-to-mealie.service
[Unit]
Description=Social Media to Mealie
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/social-to-mealie
Environment="NODE_ENV=production"
Environment="PORT=4000"
Environment="HOSTNAME=0.0.0.0"
Environment="YTDLP_PATH=./yt-dlp"
EnvironmentFile=/opt/social-to-mealie/.env
ExecStart=/usr/bin/pnpm run start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now social-to-mealie.service
msg_ok "Created and started Service"

msg_info "Creating Update Script"
cat <<'EOF' >/usr/bin/update
#!/usr/bin/env bash
# Update Script for Social Media to Mealie

set -e
echo -e "\n\e[1;34m[Info]\e[0m Stopping service..."
systemctl stop social-to-mealie.service

echo -e "\e[1;34m[Info]\e[0m Pulling source code from GitHub..."
cd /opt/social-to-mealie
git pull

echo -e "\e[1;34m[Info]\e[0m Updating yt-dlp..."
wget -q -O ./yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
chmod +x ./yt-dlp

echo -e "\e[1;34m[Info]\e[0m Installing new Node.js dependencies..."
pnpm install

echo -e "\e[1;34m[Info]\e[0m Rebuilding Next.js application..."
export NEXT_TELEMETRY_DISABLED=1
pnpm run build

echo -e "\e[1;34m[Info]\e[0m Starting service..."
systemctl start social-to-mealie.service

echo -e "\e[1;32m[Success]\e[0m Social Media to Mealie has been successfully updated!\n"
EOF

chmod +x /usr/bin/update
msg_ok "Created Update Script"

motd_ssh
customize
cleanup_lxc
