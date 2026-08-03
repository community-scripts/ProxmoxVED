#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/opencontainers/image-spec
#
# Converts any OCI/Docker image into a native Proxmox VE LXC container.
# The image is pulled with skopeo, flattened with umoci and imported as a
# regular LXC template, so the container ends up on real PVE storage and
# snapshots/backups/migration keep working. Runs on PVE 8 and 9.
#
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/tools/pve/docker2lxc.sh)"
#
# Unattended via environment:
#   OCI_IMAGE CT_NAME VMID CORES MEMORY DISK STORAGE TMPL_STORAGE NET_BRIDGE VLAN
#   IP_MODE(dhcp|static) STATIC_IP NET_GATEWAY DNS UNPRIVILEGED(0|1) NESTING(0|1)
#   START_AFTER(yes|no) EXTRA_ENV("K=V;K=V")
#   REGISTRY_CREDS("user:pass")

if ! command -v curl >/dev/null 2>&1; then
  apt-get update >/dev/null 2>&1
  apt-get install -y curl >/dev/null 2>&1
fi
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/error_handler.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/api.func) 2>/dev/null || true

load_functions
catch_errors
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "docker2lxc" "pve"

# ==============================================================================
# CONFIGURATION
# ==============================================================================
APP="Docker2LXC"
APP_TYPE="tools"

D2L_TMP=""
INIT_STRATEGY="wrapper"
TEMPLATE_VOLID=""
IMG_WORKDIR=""
IMG_USER=""
declare -a IMG_ENV=() IMG_ENTRYPOINT=() IMG_CMD=() IMG_ARGV=() IMG_PORTS=() IMG_VOLUMES=()
declare -a EXTRA_ENV_LIST=()

# ==============================================================================
# HELPERS
# ==============================================================================
have() { command -v "$1" &>/dev/null; }

abort() {
  msg_error "$1"
  [[ -n "$D2L_TMP" ]] && rm -rf "$D2L_TMP"
  exit 1
}

bail() {
  msg_warn "$1"
  [[ -n "$D2L_TMP" ]] && rm -rf "$D2L_TMP"
  exit 0
}

shq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

log_tail() { tail -n "${2:-20}" "$1" 2>/dev/null | sed 's/^/    /' >&2; }

install_deps() {
  local -a missing=()
  local pkg
  for pkg in "$@"; do
    have "$pkg" || missing+=("$pkg")
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0

  msg_info "Installing ${missing[*]}"
  $STD apt-get update
  $STD apt-get install -y "${missing[@]}"
  msg_ok "Installed ${missing[*]}"
}

# ==============================================================================
# IMAGE METADATA
# ==============================================================================
normalize_image() {
  local input="$1"
  if [[ "$input" =~ ^[^/]+[.:][^/]*/ ]]; then
    echo "$input"
  elif [[ "$input" == */* ]]; then
    echo "docker.io/$input"
  else
    echo "docker.io/library/$input"
  fi
}

fetch_image_config() {
  local ref="$1" out="$2"
  local -a auth=()
  [[ -n "${REGISTRY_CREDS:-}" ]] && auth=(--creds "$REGISTRY_CREDS")

  skopeo inspect --config "${auth[@]}" "$ref" >"$out" 2>"$D2L_TMP/skopeo.err" || {
    log_tail "$D2L_TMP/skopeo.err"
    abort "Could not read image config for $ref"
  }
}

parse_image_config() {
  local cfg="$1"

  IMG_ARCH=$(jq -r '.architecture // "amd64"' "$cfg")
  IMG_OS=$(jq -r '.os // "linux"' "$cfg")
  IMG_WORKDIR=$(jq -r '.config.WorkingDir // ""' "$cfg")
  IMG_USER=$(jq -r '.config.User // ""' "$cfg")

  mapfile -t IMG_ENV < <(jq -r '.config.Env // [] | .[]' "$cfg")
  mapfile -t IMG_ENTRYPOINT < <(jq -r '.config.Entrypoint // [] | .[]' "$cfg")
  mapfile -t IMG_CMD < <(jq -r '.config.Cmd // [] | .[]' "$cfg")
  mapfile -t IMG_PORTS < <(jq -r '.config.ExposedPorts // {} | keys[]' "$cfg")
  mapfile -t IMG_VOLUMES < <(jq -r '.config.Volumes // {} | keys[]' "$cfg")
  IMG_ARGV=("${IMG_ENTRYPOINT[@]}" "${IMG_CMD[@]}")

  [[ "$IMG_OS" == "linux" ]] || msg_warn "Image targets '$IMG_OS' - only linux images can run as LXC"
  [[ "$IMG_ARCH" == "$HOST_ARCH" ]] || msg_warn "Image is $IMG_ARCH, host is $HOST_ARCH - the container will not start"
}

detect_ostype() {
  local rootfs="$1" id=""
  if [[ -r "$rootfs/etc/os-release" ]]; then
    id=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print tolower($2); exit}' "$rootfs/etc/os-release")
  elif [[ -r "$rootfs/etc/alpine-release" ]]; then
    id="alpine"
  fi

  case "$id" in
  debian) echo debian ;;
  ubuntu) echo ubuntu ;;
  devuan) echo devuan ;;
  alpine) echo alpine ;;
  centos | rhel | rocky | almalinux | ol) echo centos ;;
  fedora) echo fedora ;;
  arch | archarm) echo archlinux ;;
  opensuse* | sles | sled) echo opensuse ;;
  gentoo) echo gentoo ;;
  nixos) echo nixos ;;
  *) echo unmanaged ;;
  esac
}

# ==============================================================================
# ROOTFS STAGING
# ==============================================================================
emit_user_switch() {
  local argv="$1" user group
  case "$IMG_USER" in
  "" | root | 0 | 0:0 | root:root) return 0 ;;
  esac
  user="${IMG_USER%%:*}"
  group=""
  [[ "$IMG_USER" == *:* ]] && group="${IMG_USER##*:}"

  echo "if command -v su >/dev/null 2>&1 && id $(shq "$user") >/dev/null 2>&1; then"
  echo "  exec su -s /bin/sh $(shq "$user") -c \"exec${argv}\""
  echo "elif command -v su-exec >/dev/null 2>&1; then"
  echo "  exec su-exec $(shq "$IMG_USER")${argv}"
  echo "elif command -v setpriv >/dev/null 2>&1; then"
  if [[ -n "$group" ]]; then
    echo "  exec setpriv --reuid $(shq "$user") --regid $(shq "$group") --clear-groups${argv}"
  else
    echo "  exec setpriv --reuid $(shq "$user") --regid \"\$(id -g $(shq "$user") 2>/dev/null || echo 0)\" --clear-groups${argv}"
  fi
  echo "fi"
  echo "echo '[docker2lxc] no su/su-exec/setpriv in image - running as root' >&2"
}

write_init_wrapper() {
  local rootfs="$1"
  local wrapper="$rootfs/.oci-entrypoint"
  local kv a argv="" has_path=0

  for kv in "${IMG_ENV[@]}"; do
    [[ "$kv" == PATH=* ]] && has_path=1
  done
  for a in "${IMG_ARGV[@]}"; do argv+=" $(shq "$a")"; done

  if [[ -z "$argv" ]]; then
    msg_warn "Image declares neither ENTRYPOINT nor CMD - using /bin/sh"
    argv=" '/bin/sh'"
  fi

  {
    echo "#!/bin/sh"
    ((has_path)) || echo 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    for kv in "${IMG_ENV[@]}" "${EXTRA_ENV_LIST[@]}"; do
      [[ "$kv" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
      echo "export ${kv%%=*}=$(shq "${kv#*=}")"
    done
    [[ -n "$IMG_WORKDIR" ]] && echo "cd $(shq "$IMG_WORKDIR") 2>/dev/null || true"
    emit_user_switch "$argv"
    echo "exec${argv}"
  } >"$wrapper"
  chmod 0755 "$wrapper"

  mkdir -p "$rootfs/sbin"
  if [[ -e "$rootfs/sbin/init" && ! -L "$rootfs/sbin/init" ]]; then
    mv "$rootfs/sbin/init" "$rootfs/sbin/init.pre-oci"
  else
    rm -f "$rootfs/sbin/init"
  fi
  ln -sf /.oci-entrypoint "$rootfs/sbin/init"
}

prepare_rootfs() {
  local rootfs="$1" dir
  msg_info "Preparing rootfs for LXC"

  for dir in proc sys dev dev/pts dev/shm run tmp var/tmp etc root; do
    mkdir -p "$rootfs/$dir"
  done
  chmod 1777 "$rootfs/tmp" "$rootfs/var/tmp"

  [[ -e "$rootfs/etc/hostname" ]] || echo "$CT_NAME" >"$rootfs/etc/hostname"
  [[ -e "$rootfs/etc/hosts" ]] || printf '127.0.0.1 localhost\n::1 localhost ip6-localhost\n' >"$rootfs/etc/hosts"
  [[ -e "$rootfs/etc/passwd" ]] || printf 'root:x:0:0:root:/root:/bin/sh\n' >"$rootfs/etc/passwd"
  [[ -e "$rootfs/etc/group" ]] || printf 'root:x:0:\n' >"$rootfs/etc/group"

  rm -f "$rootfs/etc/resolv.conf"
  printf 'nameserver %s\n' "$DNS" >"$rootfs/etc/resolv.conf"

  if [[ -x "$rootfs/bin/sh" || -L "$rootfs/bin/sh" ]]; then
    write_init_wrapper "$rootfs"
    INIT_STRATEGY="wrapper"
  else
    INIT_STRATEGY="lxc.init"
  fi

  msg_ok "Prepared rootfs"
  [[ "$INIT_STRATEGY" == "lxc.init" ]] &&
    msg_warn "Image has no /bin/sh (distroless) - using raw lxc.init.cmd instead of an init wrapper"
  return 0
}

# ==============================================================================
# NETWORKING (host-side, via the container network namespace)
# ==============================================================================
container_pid() {
  local pid
  pid=$(lxc-info -n "$1" -p -H 2>/dev/null | tr -d '[:space:]') || return 1
  [[ -n "$pid" && "$pid" != "-1" ]] || return 1
  echo "$pid"
}

netns_ip() {
  local pid=$1
  shift
  nsenter -t "$pid" -n -- ip "$@"
}

netns_current_ipv4() {
  netns_ip "$1" -4 -o addr show dev eth0 scope global 2>/dev/null | awk '{print $4; exit}'
}

apply_static_network() {
  local pid=$1
  netns_ip "$pid" link set eth0 up
  netns_ip "$pid" addr add "$STATIC_IP" dev eth0 2>/dev/null || true
  [[ -n "${NET_GATEWAY:-}" ]] &&
    { netns_ip "$pid" route replace default via "$NET_GATEWAY" dev eth0 2>/dev/null || msg_warn "Could not set default route via $NET_GATEWAY"; }
  return 0
}

apply_dhcp_network() {
  local pid=$1 hook="$D2L_TMP/dhclient-hook.sh"

  cat >"$hook" <<'HOOK'
#!/usr/bin/env bash
case "$reason" in
BOUND | RENEW | REBIND | REBOOT) ;;
*) exit 0 ;;
esac
prefix=24
if [[ -n "$new_subnet_mask" ]]; then
  p=0
  IFS=. read -ra octets <<<"$new_subnet_mask"
  for o in "${octets[@]}"; do
    while ((o > 0)); do
      ((p += o & 1))
      ((o >>= 1))
    done
  done
  prefix=$p
fi
ip link set "$interface" up
ip addr add "${new_ip_address}/${prefix}" dev "$interface" 2>/dev/null
[[ -n "$new_routers" ]] && ip route replace default via "${new_routers%% *}" dev "$interface"
exit 0
HOOK
  chmod 0755 "$hook"

  netns_ip "$pid" link set eth0 up
  nsenter -t "$pid" -n -- dhclient -1 -q \
    -sf "$hook" -lf "$D2L_TMP/dhcp.lease" -pf "$D2L_TMP/dhcp.pid" eth0 &>/dev/null || return 1
  [[ -f "$D2L_TMP/dhcp.pid" ]] && kill "$(cat "$D2L_TMP/dhcp.pid")" 2>/dev/null
  return 0
}

bring_up_network() {
  local vmid=$1 pid addr
  pid=$(container_pid "$vmid") || {
    msg_warn "Container has no PID - skipping host-side network setup"
    return 0
  }

  addr=$(netns_current_ipv4 "$pid")
  if [[ -n "$addr" ]]; then
    msg_ok "Network is up inside the container (${addr%%/*})"
    return 0
  fi

  msg_info "Configuring network from the host"
  if [[ "$IP_MODE" == "static" ]]; then
    apply_static_network "$pid"
  elif have dhclient; then
    apply_dhcp_network "$pid" || msg_warn "DHCP request failed inside the container namespace"
  else
    msg_warn "dhclient missing on the host - install isc-dhcp-client or use a static IP"
  fi

  addr=$(netns_current_ipv4 "$pid")
  if [[ -n "$addr" ]]; then
    msg_ok "Configured network (${addr%%/*})"
  else
    msg_warn "Container still has no IPv4 address on eth0"
  fi
  return 0
}

# ==============================================================================
# CONVERSION
# ==============================================================================
pick_template_storage() {
  local list
  list=$(pvesm status --content vztmpl 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}')
  [[ -z "$list" ]] && list=$(pvesm status --content vztmpl 2>/dev/null | awk 'NR>1 {print $1}')
  echo "$list" | head -1
}

build_template() {
  local ref="$1" ext="tar.zst" slug template_path
  local -a auth=()
  [[ -n "${REGISTRY_CREDS:-}" ]] && auth=(--src-creds "$REGISTRY_CREDS")

  install_deps skopeo umoci jq

  msg_info "Pulling $ref"
  skopeo copy --override-os linux --override-arch "$HOST_ARCH" "${auth[@]}" \
    "docker://$ref" "oci:$D2L_TMP/oci:converted" &>"$D2L_TMP/pull.log" || {
    msg_error "Pull failed"
    log_tail "$D2L_TMP/pull.log"
    abort "Could not pull $ref"
  }
  msg_ok "Pulled $ref"

  fetch_image_config "oci:$D2L_TMP/oci:converted" "$D2L_TMP/config.json"
  parse_image_config "$D2L_TMP/config.json"

  msg_info "Flattening layers"
  umoci unpack --image "$D2L_TMP/oci:converted" "$D2L_TMP/bundle" &>"$D2L_TMP/unpack.log" || {
    msg_error "umoci unpack failed"
    log_tail "$D2L_TMP/unpack.log"
    abort "Could not flatten $ref"
  }
  msg_ok "Flattened layers"

  OSTYPE_DETECTED=$(detect_ostype "$D2L_TMP/bundle/rootfs")
  prepare_rootfs "$D2L_TMP/bundle/rootfs"

  have zstd || ext="tar.gz"
  slug=$(echo "$ref" | sed 's|[/:]|-|g; s|[^a-zA-Z0-9._-]|-|g')
  TEMPLATE_VOLID="${TMPL_STORAGE}:vztmpl/oci-${slug}-${HOST_ARCH}.${ext}"
  template_path=$(pvesm path "$TEMPLATE_VOLID" 2>/dev/null) ||
    abort "Storage '$TMPL_STORAGE' cannot hold container templates (content type vztmpl)"
  mkdir -p "$(dirname "$template_path")"

  msg_info "Packing template"
  tar --numeric-owner --xattrs --xattrs-include='*' -caf "$template_path" -C "$D2L_TMP/bundle/rootfs" . 2>/dev/null ||
    tar --numeric-owner -caf "$template_path" -C "$D2L_TMP/bundle/rootfs" . ||
    abort "Could not pack template"
  msg_ok "Built template $TEMPLATE_VOLID ($(du -h "$template_path" | cut -f1))"
}

build_net_arg() {
  local net="name=eth0,bridge=${NET_BRIDGE}"
  [[ -n "${VLAN:-}" ]] && net+=",tag=${VLAN}"
  if [[ "$IP_MODE" == "static" ]]; then
    net+=",ip=${STATIC_IP}"
    [[ -n "${NET_GATEWAY:-}" ]] && net+=",gw=${NET_GATEWAY}"
  else
    net+=",ip=dhcp"
  fi
  echo "$net"
}

create_container_legacy() {
  local conf="/etc/pve/lxc/${VMID}.conf" entry
  local -a args=(
    "$VMID" "$TEMPLATE_VOLID"
    --hostname "$CT_NAME"
    --cores "$CORES"
    --memory "$MEMORY"
    --rootfs "${STORAGE}:${DISK}"
    --unprivileged "$UNPRIVILEGED"
    --ostype "$OSTYPE_DETECTED"
    --arch "$HOST_ARCH"
    --nameserver "$DNS"
    --net0 "$(build_net_arg)"
  )
  [[ "$NESTING" == "1" ]] && args+=(--features nesting=1)

  msg_info "Creating container $VMID"
  pct create "${args[@]}" &>"$D2L_TMP/create.log" || {
    msg_error "pct create failed"
    log_tail "$D2L_TMP/create.log" 30
    abort "Could not create container $VMID"
  }
  msg_ok "Created container $VMID"

  [[ "$INIT_STRATEGY" == "lxc.init" ]] || return 0

  {
    printf 'lxc.init.cwd: %s\n' "${IMG_WORKDIR:-/}"
    printf 'lxc.init.cmd:'
    for entry in "${IMG_ARGV[@]}"; do printf ' %s' "$entry"; done
    printf '\n'
    for entry in "${IMG_ENV[@]}" "${EXTRA_ENV_LIST[@]}"; do
      [[ "$entry" == *=* ]] && printf 'lxc.environment: %s\n' "$entry"
    done
  } >>"$conf"
  msg_ok "Wrote raw lxc.init.cmd to $conf"

  case "$IMG_USER" in
  "" | root | 0 | 0:0 | root:root) ;;
  *) msg_warn "Image wants to run as '$IMG_USER', but raw lxc.init.cmd cannot drop privileges - it will run as root" ;;
  esac
}

# ==============================================================================
# MAIN
# ==============================================================================
header_info "$APP"
root_check

have pveversion || abort "This script must be run on a Proxmox VE host"
PVE_VER=$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')
PVE_MAJOR=${PVE_VER%%.*}
PVE_MINOR=$(echo "$PVE_VER" | cut -d. -f2)
HOST_ARCH=$(dpkg --print-architecture)

msg_ok "Proxmox VE $PVE_VER on $HOST_ARCH"
((PVE_MAJOR >= 9 && PVE_MINOR >= 1)) &&
  msg_warn "PVE $PVE_VER can import OCI images itself (Storage -> CT Templates -> Pull from OCI registry)"

D2L_TMP=$(mktemp -d)

echo ""
OCI_IMAGE="${OCI_IMAGE:-$(prompt_input "OCI/Docker image (e.g. nginx:alpine, ghcr.io/user/app:1.2.3):" "nginx:alpine" 120)}"
[[ -n "$OCI_IMAGE" ]] || abort "No image specified"
FULL_IMAGE=$(normalize_image "$OCI_IMAGE")

DEFAULT_NAME=$(echo "$OCI_IMAGE" | sed 's|.*/||; s/:.*//; s/[^a-zA-Z0-9-]/-/g' | cut -c1-60)
CT_NAME="${CT_NAME:-$(prompt_input "Container hostname:" "$DEFAULT_NAME")}"
VMID="${VMID:-$(prompt_input "Container ID:" "$(pvesh get /cluster/nextid)")}"
CORES="${CORES:-$(prompt_input "CPU cores:" "2")}"
MEMORY="${MEMORY:-$(prompt_input "Memory in MB:" "1024")}"
DISK="${DISK:-$(prompt_input "Disk size in GB:" "8")}"

DEFAULT_STORAGE=$(pvesm status --content rootdir 2>/dev/null | awk 'NR>1 && $3=="active" {print $1; exit}')
STORAGE="${STORAGE:-$(prompt_input "Storage for the container rootfs:" "${DEFAULT_STORAGE:-local-lvm}")}"
TMPL_STORAGE="${TMPL_STORAGE:-$(prompt_input "Storage for the generated template:" "$(pick_template_storage)")}"
NET_BRIDGE="${NET_BRIDGE:-$(prompt_input "Network bridge:" "vmbr0")}"
VLAN="${VLAN:-$(prompt_input "VLAN tag (empty for none):" "")}"
IP_MODE="${IP_MODE:-$(prompt_select "IP mode:" 1 60 "dhcp" "static")}"

if [[ "$IP_MODE" == "static" ]]; then
  STATIC_IP="${STATIC_IP:-$(prompt_input "Static IP in CIDR notation (e.g. 192.168.1.50/24):" "")}"
  NET_GATEWAY="${NET_GATEWAY:-$(prompt_input "Gateway:" "")}"
  [[ -n "$STATIC_IP" ]] || abort "Static mode selected but no IP given"
fi
DNS="${DNS:-$(prompt_input "DNS server:" "$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null || echo 1.1.1.1)")}"

if [[ -z "${UNPRIVILEGED:-}" ]]; then
  prompt_confirm "Create as unprivileged container? (some images need privileged)" "y" && UNPRIVILEGED=1 || UNPRIVILEGED=0
fi
if [[ -z "${NESTING:-}" ]]; then
  prompt_confirm "Enable the nesting feature?" "y" && NESTING=1 || NESTING=0
fi
if [[ -z "${START_AFTER:-}" ]]; then
  prompt_confirm "Start the container after creation?" "y" && START_AFTER="yes" || START_AFTER="no"
fi

if [[ -n "${EXTRA_ENV:-}" ]]; then
  IFS=';' read -ra EXTRA_ENV_LIST <<<"$EXTRA_ENV"
elif prompt_confirm "Add custom environment variables?" "n"; then
  while true; do
    CUSTOM_ENV=$(prompt_input "KEY=VALUE (empty to finish):" "")
    [[ -z "$CUSTOM_ENV" ]] && break
    EXTRA_ENV_LIST+=("$CUSTOM_ENV")
  done
fi

echo ""
echo -e "${TAB}${BL}Image:${CL}      $FULL_IMAGE"
echo -e "${TAB}${BL}Container:${CL}  $VMID / $CT_NAME"
echo -e "${TAB}${BL}Resources:${CL}  ${CORES} cores, ${MEMORY} MB, ${DISK} GB on $STORAGE"
echo -e "${TAB}${BL}Network:${CL}    $NET_BRIDGE ${VLAN:+vlan $VLAN }($IP_MODE${STATIC_IP:+ $STATIC_IP})"
echo -e "${TAB}${BL}Privileged:${CL} $([[ "$UNPRIVILEGED" == "1" ]] && echo no || echo yes)"
echo ""

prompt_confirm "Create container $VMID from $FULL_IMAGE?" "y" || bail "Cancelled by user"
echo ""

[[ -n "$TMPL_STORAGE" ]] || abort "No storage with content type 'vztmpl' available"
build_template "$FULL_IMAGE"
create_container_legacy

if [[ "$START_AFTER" == "yes" ]]; then
  msg_info "Starting container $VMID"
  if pct start "$VMID" &>"$D2L_TMP/start.log"; then
    msg_ok "Started container $VMID"
    sleep 2
    bring_up_network "$VMID"
  else
    msg_error "Container failed to start"
    log_tail "$D2L_TMP/start.log"
    echo -e "${TAB}${YW}Debug with: pct start $VMID --debug${CL}"
  fi
fi

CT_IP=""
if PID=$(container_pid "$VMID" 2>/dev/null); then
  CT_IP=$(netns_current_ipv4 "$PID")
fi

echo ""
msg_ok "Container $VMID ($CT_NAME) created from $FULL_IMAGE"
[[ -n "$TEMPLATE_VOLID" ]] && echo -e "${TAB}${BL}Template:${CL} $TEMPLATE_VOLID"
[[ -n "$CT_IP" ]] && echo -e "${TAB}${BL}IP:${CL} ${CT_IP%%/*}"

if [[ ${#IMG_PORTS[@]} -gt 0 ]]; then
  echo -e "${TAB}${BL}Exposed ports:${CL} ${IMG_PORTS[*]}"
  [[ -n "$CT_IP" ]] && echo -e "${TAB}${BL}Try:${CL} http://${CT_IP%%/*}:${IMG_PORTS[0]%%/*}"
fi
if [[ ${#IMG_VOLUMES[@]} -gt 0 ]]; then
  msg_warn "Image declares volumes: ${IMG_VOLUMES[*]}"
  echo -e "${TAB}Persist with: pct set $VMID -mp0 ${STORAGE}:8,mp=${IMG_VOLUMES[0]}"
fi
echo -e "${TAB}${BL}Console:${CL} pct console $VMID    ${BL}Shell:${CL} pct enter $VMID"
echo ""

rm -rf "$D2L_TMP"
