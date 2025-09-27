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

# Deploy app.py automatically
cat <<'EOF' >/opt/playlistai/app.py
from flask import Flask, request, jsonify
from music_assistant_client import MusicAssistantClient
from dotenv import load_dotenv
import os, asyncio

load_dotenv("/opt/playlistai/config.env")

app = Flask(__name__)

MA_API = os.getenv("MA_API")
HA_WS_URL = os.getenv("HA_WS_URL")
TOKEN = os.getenv("TOKEN")
LLM_API = os.getenv("LLM_API")

ma_client = None

async def init_client():
    global ma_client
    if ma_client:
        return ma_client
    if HA_WS_URL and TOKEN:
        ma_client = MusicAssistantClient(HA_WS_URL, TOKEN)
    elif MA_API:
        ma_client = MusicAssistantClient(MA_API)
    else:
        raise RuntimeError("No Music Assistant endpoint configured")
    await ma_client.connect()
    return ma_client

@app.route("/generate", methods=["POST"])
def generate():
    prompt = request.json.get("prompt")
    async def fetch():
        client = await init_client()
        library = await client.get_library()
        # TODO: integrate with LLM_API here
        return [item.name for item in library]
    result = asyncio.run(fetch())
    return jsonify({"playlist": result})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

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

echo "✅ PlaylistAI installer finished. Service is ready. Start with: systemctl start playlistai"
