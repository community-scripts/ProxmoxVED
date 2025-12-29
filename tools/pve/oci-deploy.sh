#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.proxmox.com/

function header_info {
  clear
  cat <<"EOF"
   ____  ________   ______            __        _                
  / __ \/ ____/ /  / ____/___  ____  / /_____ _(_)___  ___  _____
 / / / / /   / /  / /   / __ \/ __ \/ __/ __ `/ / __ \/ _ \/ ___/
/ /_/ / /___/ /  / /___/ /_/ / / / / /_/ /_/ / / / / /  __/ /    
\____/\____/_/   \____/\____/_/ /_/\__/\__,_/_/_/ /_/\___/_/     
                                                                  
EOF
}

YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")
CM="${GN}✔️${CL}"
CROSS="${RD}✖️${CL}"
INFO="${BL}ℹ️${CL}"

APP="OCI-Container"

header_info

function msg_info() {
  local msg="$1"
  echo -e "${INFO} ${YW}${msg}...${CL}"
}

function msg_ok() {
  local msg="$1"
  echo -e "${CM} ${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${CROSS} ${RD}${msg}${CL}"
}

# Check Proxmox version
if ! command -v pveversion &>/dev/null; then
  msg_error "This script must be run on Proxmox VE"
  exit 1
fi

PVE_VER=$(pveversion | grep -oP 'pve-manager/\K[0-9.]+' | cut -d. -f1,2)
MAJOR=$(echo "$PVE_VER" | cut -d. -f1)
MINOR=$(echo "$PVE_VER" | cut -d. -f2)

if [[ "$MAJOR" -lt 9 ]] || { [[ "$MAJOR" -eq 9 ]] && [[ "$MINOR" -lt 1 ]]; }; then
  msg_error "Proxmox VE 9.1+ required (current: $PVE_VER)"
  exit 1
fi

msg_ok "Proxmox VE $PVE_VER detected"

# Parse OCI image
parse_image() {
  local input="$1"
  if [[ "$input" =~ ^([^/]+\.[^/]+)/ ]]; then
    echo "$input"
  elif [[ "$input" =~ / ]]; then
    echo "docker.io/$input"
  else
    echo "docker.io/library/$input"
  fi
}

# Interactive image selection
if [[ -z "${OCI_IMAGE:-}" ]]; then
  echo ""
  echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
  echo -e "${BL}Select OCI Image:${CL}"
  echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
  echo -e "  ${BL}1)${CL} nginx:alpine          - Lightweight web server"
  echo -e "  ${BL}2)${CL} postgres:16-alpine    - PostgreSQL database"
  echo -e "  ${BL}3)${CL} redis:alpine          - Redis cache"
  echo -e "  ${BL}4)${CL} mariadb:latest        - MariaDB database"
  echo -e "  ${BL}5)${CL} ghcr.io/linkwarden/linkwarden:latest"
  echo -e "  ${BL}6)${CL} Custom image"
  echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
  echo ""

  read -r -p "Select option (1-6): " IMAGE_CHOICE

  case $IMAGE_CHOICE in
  1) OCI_IMAGE="nginx:alpine" ;;
  2) OCI_IMAGE="postgres:16-alpine" ;;
  3) OCI_IMAGE="redis:alpine" ;;
  4) OCI_IMAGE="mariadb:latest" ;;
  5) OCI_IMAGE="ghcr.io/linkwarden/linkwarden:latest" ;;
  6)
    read -r -p "Enter OCI image (e.g., ghcr.io/user/repo:tag): " OCI_IMAGE
    [[ -z "$OCI_IMAGE" ]] && {
      msg_error "No image specified"
      exit 1
    }
    ;;
  *)
    msg_error "Invalid choice"
    exit 1
    ;;
  esac
fi

FULL_IMAGE=$(parse_image "$OCI_IMAGE")
msg_ok "Selected: $FULL_IMAGE"

# Derive container name
if [[ -z "${CT_NAME:-}" ]]; then
  DEFAULT_NAME=$(echo "$OCI_IMAGE" | sed 's|.*/||; s/:.*//; s/[^a-zA-Z0-9-]/-/g' | cut -c1-60)
  read -r -p "Container name [${DEFAULT_NAME}]: " CT_NAME
  CT_NAME=${CT_NAME:-$DEFAULT_NAME}
fi

# Get next VMID
if [[ -z "${VMID:-}" ]]; then
  NEXT_ID=$(pvesh get /cluster/nextid)
  read -r -p "Container ID [${NEXT_ID}]: " VMID
  VMID=${VMID:-$NEXT_ID}
fi

# Resources
if [[ -z "${CORES:-}" ]]; then
  read -r -p "CPU cores [2]: " CORES
  CORES=${CORES:-2}
fi

if [[ -z "${MEMORY:-}" ]]; then
  read -r -p "Memory in MB [2048]: " MEMORY
  MEMORY=${MEMORY:-2048}
fi

if [[ -z "${DISK:-}" ]]; then
  read -r -p "Disk size in GB [8]: " DISK
  DISK=${DISK:-8}
fi

# Storage
if [[ -z "${STORAGE:-}" ]]; then
  AVAIL_STORAGE=$(pvesm status | awk '/^local-(zfs|lvm)/ {print $1; exit}')
  [[ -z "$AVAIL_STORAGE" ]] && AVAIL_STORAGE="local"
  read -r -p "Storage [${AVAIL_STORAGE}]: " STORAGE
  STORAGE=${STORAGE:-$AVAIL_STORAGE}
fi

# Network
if [[ -z "${BRIDGE:-}" ]]; then
  read -r -p "Network bridge [vmbr0]: " BRIDGE
  BRIDGE=${BRIDGE:-vmbr0}
fi

if [[ -z "${IP_MODE:-}" ]]; then
  read -r -p "IP mode (dhcp/static) [dhcp]: " IP_MODE
  IP_MODE=${IP_MODE:-dhcp}
fi

if [[ "$IP_MODE" == "static" ]]; then
  read -r -p "Static IP (CIDR, e.g., 192.168.1.100/24): " STATIC_IP
  read -r -p "Gateway IP: " GATEWAY
fi

# Environment variables
declare -a ENV_VARS=()

case "$OCI_IMAGE" in
postgres* | postgresql*)
  echo ""
  msg_info "PostgreSQL requires environment variables"
  read -r -p "PostgreSQL password: " -s PG_PASS
  echo ""
  ENV_VARS+=("POSTGRES_PASSWORD=$PG_PASS")

  read -r -p "Create database (optional): " PG_DB
  [[ -n "$PG_DB" ]] && ENV_VARS+=("POSTGRES_DB=$PG_DB")

  read -r -p "PostgreSQL user (optional): " PG_USER
  [[ -n "$PG_USER" ]] && ENV_VARS+=("POSTGRES_USER=$PG_USER")
  ;;

mariadb* | mysql*)
  echo ""
  msg_info "MariaDB/MySQL requires environment variables"
  read -r -p "Root password: " -s MYSQL_PASS
  echo ""
  ENV_VARS+=("MYSQL_ROOT_PASSWORD=$MYSQL_PASS")

  read -r -p "Create database (optional): " MYSQL_DB
  [[ -n "$MYSQL_DB" ]] && ENV_VARS+=("MYSQL_DATABASE=$MYSQL_DB")

  read -r -p "Create user (optional): " MYSQL_USER
  if [[ -n "$MYSQL_USER" ]]; then
    ENV_VARS+=("MYSQL_USER=$MYSQL_USER")
    read -r -p "User password: " -s MYSQL_USER_PASS
    echo ""
    ENV_VARS+=("MYSQL_PASSWORD=$MYSQL_USER_PASS")
  fi
  ;;

*linkwarden*)
  echo ""
  msg_info "Linkwarden configuration"
  read -r -p "NEXTAUTH_SECRET (press Enter to generate): " NEXTAUTH_SECRET
  if [[ -z "$NEXTAUTH_SECRET" ]]; then
    NEXTAUTH_SECRET=$(openssl rand -base64 32)
  fi
  ENV_VARS+=("NEXTAUTH_SECRET=$NEXTAUTH_SECRET")

  read -r -p "NEXTAUTH_URL [http://localhost:3000]: " NEXTAUTH_URL
  NEXTAUTH_URL=${NEXTAUTH_URL:-http://localhost:3000}
  ENV_VARS+=("NEXTAUTH_URL=$NEXTAUTH_URL")

  read -r -p "DATABASE_URL (PostgreSQL connection string): " DATABASE_URL
  [[ -n "$DATABASE_URL" ]] && ENV_VARS+=("DATABASE_URL=$DATABASE_URL")
  ;;
esac

# Additional env vars
read -r -p "Add custom environment variables? (y/N): " ADD_ENV
if [[ "${ADD_ENV,,}" =~ ^(y|yes)$ ]]; then
  while true; do
    read -r -p "Enter KEY=VALUE (or press Enter to finish): " CUSTOM_ENV
    [[ -z "$CUSTOM_ENV" ]] && break
    ENV_VARS+=("$CUSTOM_ENV")
  done
fi

# Privileged mode
read -r -p "Run as privileged container? (y/N): " PRIV_MODE
if [[ "${PRIV_MODE,,}" =~ ^(y|yes)$ ]]; then
  UNPRIVILEGED="0"
else
  UNPRIVILEGED="1"
fi

# Auto-start
read -r -p "Start container after creation? (Y/n): " AUTO_START
if [[ "${AUTO_START,,}" =~ ^(n|no)$ ]]; then
  START_AFTER="no"
else
  START_AFTER="yes"
fi

# Summary
echo ""
echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "${BL}Container Configuration Summary:${CL}"
echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo -e "  Image:      $FULL_IMAGE"
echo -e "  ID:         $VMID"
echo -e "  Name:       $CT_NAME"
echo -e "  CPUs:       $CORES"
echo -e "  Memory:     ${MEMORY}MB"
echo -e "  Disk:       ${DISK}GB"
echo -e "  Storage:    $STORAGE"
echo -e "  Network:    $BRIDGE ($IP_MODE)"
[[ ${#ENV_VARS[@]} -gt 0 ]] && echo -e "  Env vars:   ${#ENV_VARS[@]} configured"
echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
echo ""

read -r -p "Proceed with creation? (Y/n): " CONFIRM
if [[ "${CONFIRM,,}" =~ ^(n|no)$ ]]; then
  msg_error "Cancelled by user"
  exit 0
fi

# Create container
msg_info "Creating container $VMID"

# Build pct create command
PCT_CMD="pct create $VMID"
PCT_CMD+=" --hostname $CT_NAME"
PCT_CMD+=" --cores $CORES"
PCT_CMD+=" --memory $MEMORY"
PCT_CMD+=" --rootfs ${STORAGE}:${DISK},oci=${FULL_IMAGE}"
PCT_CMD+=" --unprivileged $UNPRIVILEGED"

if [[ "$IP_MODE" == "static" && -n "$STATIC_IP" ]]; then
  PCT_CMD+=" --net0 name=eth0,bridge=$BRIDGE,ip=$STATIC_IP"
  [[ -n "$GATEWAY" ]] && PCT_CMD+=",gw=$GATEWAY"
else
  PCT_CMD+=" --net0 name=eth0,bridge=$BRIDGE,ip=dhcp"
fi

if eval "$PCT_CMD" 2>&1; then
  msg_ok "Container created"
else
  msg_error "Failed to create container"
  exit 1
fi

# Set environment variables
if [[ ${#ENV_VARS[@]} -gt 0 ]]; then
  msg_info "Configuring environment variables"
  for env_var in "${ENV_VARS[@]}"; do
    if pct set "$VMID" -env "$env_var" &>/dev/null; then
      :
    else
      msg_error "Failed to set: $env_var"
    fi
  done
  msg_ok "Environment variables configured (${#ENV_VARS[@]} variables)"
fi

# Start container
if [[ "$START_AFTER" == "yes" ]]; then
  msg_info "Starting container"
  if pct start "$VMID" 2>&1; then
    msg_ok "Container started"

    # Wait for network
    sleep 3
    CT_IP=$(pct exec "$VMID" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")

    echo ""
    echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo -e "${BL}Container Information:${CL}"
    echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo -e "  ID:       ${GN}$VMID${CL}"
    echo -e "  Name:     ${GN}$CT_NAME${CL}"
    echo -e "  Image:    ${GN}$FULL_IMAGE${CL}"
    echo -e "  IP:       ${GN}$CT_IP${CL}"
    echo -e "  Status:   ${GN}Running${CL}"
    echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo ""
    echo -e "${INFO} ${YW}Access console:${CL} pct console $VMID"
    echo -e "${INFO} ${YW}View logs:${CL}      pct logs $VMID"
    echo ""
  else
    msg_error "Failed to start container"
  fi
else
  echo ""
  echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
  echo -e "${BL}Container Information:${CL}"
  echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
  echo -e "  ID:       ${GN}$VMID${CL}"
  echo -e "  Name:     ${GN}$CT_NAME${CL}"
  echo -e "  Image:    ${GN}$FULL_IMAGE${CL}"
  echo -e "  Status:   ${YW}Stopped${CL}"
  echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
  echo ""
  echo -e "${INFO} ${YW}Start with:${CL} pct start $VMID"
  echo ""
fi
