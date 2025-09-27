#!/usr/bin/env bash
# PlaylistAI Installer Script
# Runs inside the LXC container
# Author: Michael (Hoosier-IT)

set -e

echo "⚙️ Installing PlaylistAI dependencies..."

# Update and install base packages
apt-get update
apt-get install -y python3 python3-pip python3-venv git curl

# Create app directory
mkdir -p /opt/playlistai
cd /opt/playlistai

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install flask music-assistant-client requests python-dotenv

# Create config.env if missing
if [ ! -f /opt/playlistai/config.env ]; then
cat <<EOF >/opt/playlistai/config.env
# PlaylistAI Configuration
MA_API=http://192.168.1.100:8095
HA_WS_URL=ws://homeassistant.local:8123/api/websocket
TOKEN=your_long_lived_token_here
LLM_API=http://127.0.0.1:11434/v1/chat/completions
MUSIC_PATH=/mnt/music
EOF
fi

# Write systemd service
cat <<EOF >/etc/systemd/system/playlistai.service
[Unit]
Description=PlaylistAI Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/playlistai
EnvironmentFile=/opt/playlistai/config.env
ExecStart=/opt/playlistai/venv/bin/python /opt/playlistai/app.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable playlistai

echo "✅ PlaylistAI installer finished. Place your app.py in /opt/playlistai and start with: systemctl start playlistai"
