!/usr/bin/env bash
# ------------------------------------------------------------------
# Proxmox VE Helper Script
# Title: Termix
# Description: Termix Web-based SSH manager using Docker
# Author: CtrlSync 
# License: MIT (same as ProxmoxVE community scripts)
# ------------------------------------------------------------------

set -e

echo "=============================="
echo "  Termix LXC Installer"
echo "=============================="
echo ""

### ---- USER PROMPTS ----

read -rp "Container ID (CTID): " CTID
if [[ -z "$CTID" ]]; then
  echo "❌ CTID is required"
  exit 1
fi

read -rp "Hostname [termix]: " HOSTNAME
HOSTNAME=${HOSTNAME:-termix}

read -rp "Memory in MB [1024]: " MEMORY
MEMORY=${MEMORY:-1024}

read -rp "Disk size in GB [12]: " DISK
DISK=${DISK:-12}

read -rp "Web UI Port [8080]: " PORT
PORT=${PORT:-8080}

read -rp "Use DHCP? [Y/n]: " USE_DHCP
USE_DHCP=${USE_DHCP:-Y}

if [[ "$USE_DHCP" =~ ^[Nn]$ ]]; then
  read -rp "Static IP (CIDR, e.g. 192.168.1.50/24): " IP_ADDR
  read -rp "Gateway (e.g. 192.168.1.1): " GATEWAY
  NETCONF="ip=${IP_ADDR},gw=${GATEWAY}"
else
  NETCONF="ip=dhcp"
fi

BRIDGE="vmbr0"

echo ""
echo "➡️  CTID:      $CTID"
echo "➡️  Hostname:  $HOSTNAME"
echo "➡️  Memory:    ${MEMORY}MB"
echo "➡️  Disk:      ${DISK}GB"
echo "➡️  Web Port:  $PORT"
echo ""

read -rp "Proceed with installation? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "❌ Aborted."
  exit 0
fi

### ---- AUTO-DETECT TEMPLATE ----

echo ""
echo "🔍 Detecting latest Debian 12 template..."

TEMPLATE=$(pveam available --section system | grep debian-12 | tail -n 1 | awk '{print $2}')

if [[ -z "$TEMPLATE" ]]; then
  echo "❌ Could not find Debian 12 template"
  exit 1
fi

echo "📦 Using template: $TEMPLATE"

if ! pveam list local | grep -q "$TEMPLATE"; then
  echo "⬇️  Downloading template..."
  pveam download local "$TEMPLATE"
fi

### ---- AUTO-DETECT STORAGE ----

echo "🔍 Detecting storage backend..."

STORAGE=$(pvesm status -content rootdir | awk 'NR==2 {print $1}')

if [[ -z "$STORAGE" ]]; then
  echo "❌ Could not detect storage"
  exit 1
fi

echo "💾 Using storage: $STORAGE"

### ---- CREATE CONTAINER ----

echo ""
echo "🚀 Creating LXC..."

pct create "$CTID" "local:vztmpl/$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --cores 1 \
  --memory "$MEMORY" \
  --swap 1024 \
  --rootfs "${STORAGE}:${DISK}" \
  --net0 name=eth0,bridge="$BRIDGE",$NETCONF \
  --unprivileged 1 \
  --features nesting=1 \
  --onboot 1
echo "▶️  Starting container..."
pct start "$CTID"

echo "⏳ Waiting for container to boot..."
sleep 10

### ---- INSTALL DOCKER ----

echo "🐳 Installing Docker..."

pct exec "$CTID" -- bash <<'EOF'
apt update
apt install -y ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
EOF

### ---- DEPLOY TERMIX ----

echo "🖥️  Deploying Termix..."

pct exec "$CTID" -- bash -c "
docker volume create termix-data &&
docker run -d \
  --name termix \
  --restart unless-stopped \
  -p ${PORT}:8080 \
  -v termix-data:/app/data \
  -e PORT=8080 \
  ghcr.io/lukegus/termix:latest
"

echo ""
echo "✅ Termix installation complete!"
echo "🌐 Access it at: http://<container-ip>:${PORT}"
echo ""
