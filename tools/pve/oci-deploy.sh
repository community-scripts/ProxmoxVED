#!/usr/bin/env bash
# Maintainer: MickLesk (CanbiZ)
# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# OCI Container Deployment Helper for Proxmox VE 9.1+

set -euo pipefail
shopt -s inherit_errexit nullglob

# Color codes
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

# Check if running on Proxmox VE 9.1+
check_proxmox_version() {
  if ! command -v pveversion &>/dev/null; then
    msg_error "This script must be run on Proxmox VE"
    exit 1
  fi

  local pve_version=$(pveversion | grep -oP 'pve-manager/\K[0-9.]+' | cut -d. -f1,2)
  local major=$(echo "$pve_version" | cut -d. -f1)
  local minor=$(echo "$pve_version" | cut -d. -f2)

  if [[ "$major" -lt 9 ]] || { [[ "$major" -eq 9 ]] && [[ "$minor" -lt 1 ]]; }; then
    msg_error "Proxmox VE 9.1 or higher required (current: $pve_version)"
    exit 1
  fi
}

# Parse OCI image reference
parse_image_ref() {
  local image_ref="$1"
  local registry=""
  local image=""
  local tag="latest"

  # Handle different formats:
  # - nginx:latest
  # - docker.io/library/nginx:latest
  # - ghcr.io/user/repo:tag

  if [[ "$image_ref" =~ ^([^/]+\.[^/]+)/ ]]; then
    # Has registry prefix (contains dot)
    registry="${BASH_REMATCH[1]}"
    image_ref="${image_ref#*/}"
  else
    # Use docker.io as default
    registry="docker.io"
  fi

  # Extract tag if present
  if [[ "$image_ref" =~ :([^:]+)$ ]]; then
    tag="${BASH_REMATCH[1]}"
    image="${image_ref%:*}"
  else
    image="$image_ref"
  fi

  # Add library/ prefix for official docker hub images
  if [[ "$registry" == "docker.io" ]] && [[ ! "$image" =~ / ]]; then
    image="library/$image"
  fi

  echo "$registry/$image:$tag"
}

# Show usage
usage() {
  cat <<EOF
${GN}OCI Container Deployment Tool for Proxmox VE 9.1+${CL}

Usage: $(basename "$0") [OPTIONS] IMAGE

${BL}Arguments:${CL}
  IMAGE                 OCI image reference (e.g., nginx:latest, ghcr.io/user/repo:tag)

${BL}Options:${CL}
  -n, --name NAME       Container name (default: derived from image)
  -i, --vmid ID         Container ID (default: next available)
  -c, --cores NUM       CPU cores (default: 2)
  -m, --memory MB       RAM in MB (default: 2048)
  -d, --disk GB         Root disk size in GB (default: 8)
  -s, --storage NAME    Storage name (default: local-zfs or local-lvm)
  --network BRIDGE      Network bridge (default: vmbr0)
  --ip CIDR             Static IP with CIDR (e.g., 192.168.1.100/24)
  --gateway IP          Gateway IP
  -e, --env KEY=VALUE   Environment variable (can be used multiple times)
  -v, --volume PATH     Mount point as PATH:SIZE (e.g., /data:10G)
  --privileged          Create privileged container
  --start               Start container after creation
  -h, --help            Show this help

${BL}Examples:${CL}
  # Deploy nginx with defaults
  $(basename "$0") nginx:latest

  # Deploy with custom settings
  $(basename "$0") -n my-app -c 4 -m 4096 -e DOMAIN=example.com ghcr.io/user/app:latest

  # Deploy with volume and static IP
  $(basename "$0") -v /data:20G --ip 192.168.1.100/24 --gateway 192.168.1.1 postgres:16

EOF
  exit 0
}

# Main deployment function
deploy_oci_container() {
  local image="$1"
  local name="${2:-}"
  local vmid="${3:-}"
  local cores="${4:-2}"
  local memory="${5:-2048}"
  local disk="${6:-8}"
  local storage="${7:-}"
  local network="${8:-vmbr0}"
  local ip="${9:-dhcp}"
  local gateway="${10:-}"
  local privileged="${11:-0}"
  local start_after="${12:-0}"
  shift 12
  local env_vars=("$@")

  msg_info "Checking Proxmox version"
  check_proxmox_version
  msg_ok "Proxmox version compatible"

  # Parse image reference
  local full_image=$(parse_image_ref "$image")
  msg_info "Parsing image reference: $full_image"
  msg_ok "Image reference parsed"

  # Derive name from image if not specified
  if [[ -z "$name" ]]; then
    name=$(echo "$image" | sed 's/[^a-zA-Z0-9-]/-/g' | sed 's/:/-/g' | cut -c1-60)
  fi

  # Get next available VMID if not specified
  if [[ -z "$vmid" ]]; then
    vmid=$(pvesh get /cluster/nextid)
  fi

  # Determine storage
  if [[ -z "$storage" ]]; then
    if pvesm status | grep -q "local-zfs"; then
      storage="local-zfs"
    elif pvesm status | grep -q "local-lvm"; then
      storage="local-lvm"
    else
      storage="local"
    fi
  fi

  msg_info "Creating container $vmid ($name) from $full_image"

  # Create container using pct
  local pct_cmd="pct create $vmid"
  pct_cmd+=" --ostemplate oci://$full_image"
  pct_cmd+=" --hostname $name"
  pct_cmd+=" --cores $cores"
  pct_cmd+=" --memory $memory"
  pct_cmd+=" --rootfs ${storage}:${disk}"
  pct_cmd+=" --net0 name=eth0,bridge=$network"

  if [[ "$ip" != "dhcp" ]]; then
    pct_cmd+=",ip=$ip"
    [[ -n "$gateway" ]] && pct_cmd+=",gw=$gateway"
  else
    pct_cmd+=",ip=dhcp"
  fi

  [[ "$privileged" == "1" ]] && pct_cmd+=" --unprivileged 0" || pct_cmd+=" --unprivileged 1"

  # Execute container creation
  if ! eval "$pct_cmd" 2>/dev/null; then
    msg_error "Failed to create container"
    exit 1
  fi

  msg_ok "Container created (ID: $vmid)"

  # Set environment variables if provided
  if [[ ${#env_vars[@]} -gt 0 ]]; then
    msg_info "Configuring environment variables"
    for env_var in "${env_vars[@]}"; do
      local key="${env_var%%=*}"
      local value="${env_var#*=}"
      pct set "$vmid" --env "$key=$value" >/dev/null 2>&1
    done
    msg_ok "Environment variables configured (${#env_vars[@]} variables)"
  fi

  # Start container if requested
  if [[ "$start_after" == "1" ]]; then
    msg_info "Starting container"
    if pct start "$vmid" >/dev/null 2>&1; then
      msg_ok "Container started successfully"

      # Wait for network
      sleep 3
      local container_ip=$(pct exec "$vmid" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")

      echo -e "\n${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
      echo -e "${BL}Container Information:${CL}"
      echo -e "  ID:       ${GN}$vmid${CL}"
      echo -e "  Name:     ${GN}$name${CL}"
      echo -e "  Image:    ${GN}$full_image${CL}"
      echo -e "  IP:       ${GN}$container_ip${CL}"
      echo -e "  Status:   ${GN}Running${CL}"
      echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}\n"
    else
      msg_error "Failed to start container"
    fi
  else
    echo -e "\n${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo -e "${BL}Container Information:${CL}"
    echo -e "  ID:       ${GN}$vmid${CL}"
    echo -e "  Name:     ${GN}$name${CL}"
    echo -e "  Image:    ${GN}$full_image${CL}"
    echo -e "  Status:   ${YW}Stopped${CL}"
    echo -e "\n${YW}Start with: pct start $vmid${CL}"
    echo -e "${GN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}\n"
  fi
}

# Parse command line arguments
IMAGE=""
NAME=""
VMID=""
CORES="2"
MEMORY="2048"
DISK="8"
STORAGE=""
NETWORK="vmbr0"
IP="dhcp"
GATEWAY=""
PRIVILEGED="0"
START="0"
ENV_VARS=()
VOLUMES=()

while [[ $# -gt 0 ]]; do
  case $1 in
  -h | --help)
    usage
    ;;
  -n | --name)
    NAME="$2"
    shift 2
    ;;
  -i | --vmid)
    VMID="$2"
    shift 2
    ;;
  -c | --cores)
    CORES="$2"
    shift 2
    ;;
  -m | --memory)
    MEMORY="$2"
    shift 2
    ;;
  -d | --disk)
    DISK="$2"
    shift 2
    ;;
  -s | --storage)
    STORAGE="$2"
    shift 2
    ;;
  --network)
    NETWORK="$2"
    shift 2
    ;;
  --ip)
    IP="$2"
    shift 2
    ;;
  --gateway)
    GATEWAY="$2"
    shift 2
    ;;
  -e | --env)
    ENV_VARS+=("$2")
    shift 2
    ;;
  -v | --volume)
    VOLUMES+=("$2")
    shift 2
    ;;
  --privileged)
    PRIVILEGED="1"
    shift
    ;;
  --start)
    START="1"
    shift
    ;;
  -*)
    echo "Unknown option: $1"
    usage
    ;;
  *)
    IMAGE="$1"
    shift
    ;;
  esac
done

# Check if image is provided
if [[ -z "$IMAGE" ]]; then
  msg_error "No image specified"
  usage
fi

# Deploy the container
deploy_oci_container "$IMAGE" "$NAME" "$VMID" "$CORES" "$MEMORY" "$DISK" "$STORAGE" "$NETWORK" "$IP" "$GATEWAY" "$PRIVILEGED" "$START" "${ENV_VARS[@]}"

exit 0
