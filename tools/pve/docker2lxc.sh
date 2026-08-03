#!/usr/bin/env bash
#
# Title: Docker/OCI Image to Proxmox LXC Converter (experimental)
# Description: Converts any OCI/Docker image into a native Proxmox VE LXC container.
#              On PVE 9.1+ the built-in `pct create --rootfs oci=` path is used.
#              On older releases the image is pulled with skopeo, flattened with
#              umoci and imported as a regular LXC template, so the container ends
#              up on real PVE storage (snapshots/backups/migration keep working).
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Author: MickLesk (CanbiZ)
# Repo: https://github.com/community-scripts/ProxmoxVED
#
# Usage: bash -c "$(curl -fsSL https://github.com/community-scripts/ProxmoxVED/raw/main/tools/pve/docker2lxc.sh)"
#
# Unattended via environment:
#   OCI_IMAGE CT_NAME VMID CORES MEMORY DISK STORAGE TMPL_STORAGE BRIDGE VLAN
#   IP_MODE(dhcp|static) STATIC_IP GATEWAY DNS UNPRIVILEGED(0|1) NESTING(0|1)
#   START_AFTER(yes|no) CONVERT_MODE(auto|native|legacy) EXTRA_ENV("K=V;K=V")
#   REGISTRY_CREDS("user:pass") ASSUME_YES(1)

set -Eeuo pipefail

YW="\033[33m"
GN="\033[1;92m"
RD="\033[01;31m"
BL="\033[36m"
CL="\033[m"
CM="${GN}✔${CL}"
CROSS="${RD}✖${CL}"
INFO="${BL}➤${CL}"
WARN="${YW}⚠${CL}"

TMP_DIR=""
CREATED_VMID=""
INIT_STRATEGY="wrapper"
declare -a IMG_ENV=() IMG_ENTRYPOINT=() IMG_CMD=() IMG_ARGV=() IMG_PORTS=() IMG_VOLUMES=()
declare -a EXTRA_ENV_LIST=()
IMG_WORKDIR="" IMG_USER=""

msg_info() { echo -e " ${INFO} ${YW}$1...${CL}"; }
msg_ok() { echo -e " ${CM} ${GN}$1${CL}"; }
msg_warn() { echo -e " ${WARN} ${YW}$1${CL}" >&2; }
msg_error() { echo -e " ${CROSS} ${RD}$1${CL}" >&2; }

header_info() {
  clear
  cat <<"EOF"
    ____             __              ___    __   _  ________
   / __ \____  _____/ /_____  _____ |__ \  / /  | |/ / ____/
  / / / / __ \/ ___/ //_/ _ \/ ___/ __/ / / /   |   / /
 / /_/ / /_/ / /__/ ,< /  __/ /   / __/ / / /___/   / /___
/_____/\____/\___/_/|_|\___/_/   /____/ /_____/_/|_\____/

   Docker/OCI Image  ->  Proxmox VE LXC   (experimental)
EOF
  echo ""
}

cleanup() {
  local rc=$?
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
  if [[ $rc -ne 0 && -n "$CREATED_VMID" ]]; then
    msg_warn "Aborted after container $CREATED_VMID was created - remove it with: pct destroy $CREATED_VMID"
  fi
  return $rc
}
trap cleanup EXIT
trap 'msg_error "Failed at line $LINENO: $BASH_COMMAND"' ERR

have() { command -v "$1" &>/dev/null; }

shq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

# ------------------------------------------------------------------ preflight

preflight() {
  [[ "$(id -u)" -eq 0 ]] || {
    msg_error "This script must be run as root"
    exit 1
  }
  have pveversion || {
    msg_error "This script must be run on a Proxmox VE host"
    exit 1
  }

  PVE_VER=$(pveversion | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+')
  PVE_MAJOR=${PVE_VER%%.*}
  PVE_MINOR=${PVE_VER##*.}
  msg_ok "Proxmox VE $PVE_VER detected"

  if ((PVE_MAJOR > 9)) || { ((PVE_MAJOR == 9)) && ((PVE_MINOR >= 1)); }; then
    NATIVE_OCI=1
  else
    NATIVE_OCI=0
  fi

  HOST_ARCH=$(dpkg --print-architecture)
}

install_deps() {
  local -a missing=()
  local pkg
  for pkg in "$@"; do
    have "$pkg" || missing+=("$pkg")
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0

  msg_info "Installing missing tools: ${missing[*]}"
  apt-get update -qq &>/dev/null || true
  if ! apt-get install -y -qq "${missing[@]}" &>/dev/null; then
    msg_error "Could not install: ${missing[*]}"
    exit 1
  fi
  msg_ok "Installed: ${missing[*]}"
}

ensure_whiptail() {
  have whiptail || install_deps whiptail
}

# ------------------------------------------------------------------- prompts

ask() {
  local var="$1" label default="${3:-}"
  label=$(printf '%b' "$2")
  local current="${!var:-}"
  if [[ -n "$current" ]]; then
    printf -v "$var" '%s' "$current"
    return 0
  fi
  local value
  value=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker to LXC" \
    --inputbox "$label" 11 72 "$default" 3>&1 1>&2 2>&3) || {
    msg_error "Cancelled by user"
    exit 1
  }
  printf -v "$var" '%s' "${value:-$default}"
}

ask_yesno() {
  local var="$1" label default="${3:-yes}"
  label=$(printf '%b' "$2")
  [[ -n "${!var:-}" ]] && return 0
  local flag=""
  [[ "$default" == "no" ]] && flag="--defaultno"
  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker to LXC" \
    $flag --yesno "$label" 11 72; then
    printf -v "$var" '%s' "yes"
  else
    printf -v "$var" '%s' "no"
  fi
}

# --------------------------------------------------------------- image config

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

skopeo_auth_args() {
  [[ -n "${REGISTRY_CREDS:-}" ]] && printf '%s\n%s\n' "--creds" "$REGISTRY_CREDS"
  return 0
}

fetch_image_config() {
  local ref="$1" out="$2"
  local -a auth=()
  mapfile -t auth < <(skopeo_auth_args)
  skopeo inspect --config "${auth[@]}" "$ref" >"$out" 2>"$TMP_DIR/skopeo.err" || {
    msg_error "Could not read image config for $ref"
    sed 's/^/    /' "$TMP_DIR/skopeo.err" >&2
    exit 1
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

  [[ "$IMG_OS" != "linux" ]] && msg_warn "Image OS is '$IMG_OS' - only linux images work as LXC"
  if [[ "$IMG_ARCH" != "$HOST_ARCH" ]]; then
    msg_warn "Image architecture '$IMG_ARCH' differs from host '$HOST_ARCH' - the container will not run"
  fi
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

# ------------------------------------------------------------- rootfs staging

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
    msg_warn "Image declares neither ENTRYPOINT nor CMD - falling back to /bin/sh"
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
  local rootfs="$1" d
  msg_info "Preparing rootfs for LXC"

  for d in proc sys dev dev/pts dev/shm run tmp var/tmp etc root; do
    mkdir -p "$rootfs/$d"
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
    msg_warn "No /bin/sh in image (distroless) - using raw lxc.init.cmd instead of an init wrapper"
  fi

  msg_ok "Rootfs prepared"
}

# ------------------------------------------------------------------ networking

mask2prefix() {
  local mask=$1 prefix=0 octet
  local IFS=.
  for octet in $mask; do
    case $octet in
    255) prefix=$((prefix + 8)) ;;
    254) prefix=$((prefix + 7)) ;;
    252) prefix=$((prefix + 6)) ;;
    248) prefix=$((prefix + 5)) ;;
    240) prefix=$((prefix + 4)) ;;
    224) prefix=$((prefix + 3)) ;;
    192) prefix=$((prefix + 2)) ;;
    128) prefix=$((prefix + 1)) ;;
    esac
  done
  echo "$prefix"
}

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
  if [[ -n "${GATEWAY:-}" ]]; then
    netns_ip "$pid" route replace default via "$GATEWAY" dev eth0 2>/dev/null ||
      msg_warn "Could not set default route via $GATEWAY"
  fi
}

apply_dhcp_network() {
  local pid=$1
  netns_ip "$pid" link set eth0 up

  local script="$TMP_DIR/dhclient-hook.sh"
  cat >"$script" <<'HOOK'
#!/usr/bin/env bash
case "$reason" in
BOUND | RENEW | REBIND | REBOOT) ;;
*) exit 0 ;;
esac
prefix=24
if [[ -n "$new_subnet_mask" ]]; then
  p=0
  IFS=. read -ra o <<<"$new_subnet_mask"
  for x in "${o[@]}"; do
    while ((x > 0)); do
      ((p += x & 1))
      ((x >>= 1))
    done
  done
  prefix=$p
fi
ip link set "$interface" up
ip addr add "${new_ip_address}/${prefix}" dev "$interface" 2>/dev/null
[[ -n "$new_routers" ]] && ip route replace default via "${new_routers%% *}" dev "$interface"
exit 0
HOOK
  chmod 0755 "$script"

  if ! nsenter -t "$pid" -n -- dhclient -1 -q \
    -sf "$script" -lf "$TMP_DIR/dhcp.lease" -pf "$TMP_DIR/dhcp.pid" eth0 &>/dev/null; then
    return 1
  fi
  [[ -f "$TMP_DIR/dhcp.pid" ]] && kill "$(cat "$TMP_DIR/dhcp.pid")" 2>/dev/null || true
  return 0
}

bring_up_network() {
  local vmid=$1 pid ip
  pid=$(container_pid "$vmid") || {
    msg_warn "Container has no PID - skipping host-side network setup"
    return 0
  }

  ip=$(netns_current_ipv4 "$pid")
  if [[ -n "$ip" ]]; then
    msg_ok "Network already up inside container ($ip)"
    return 0
  fi

  msg_info "Configuring network from host (nsenter)"
  if [[ "$IP_MODE" == "static" ]]; then
    apply_static_network "$pid"
  else
    if ! have dhclient; then
      msg_warn "dhclient not present on host - install isc-dhcp-client or use a static IP"
      return 0
    fi
    apply_dhcp_network "$pid" || msg_warn "DHCP request failed inside container namespace"
  fi

  ip=$(netns_current_ipv4 "$pid")
  if [[ -n "$ip" ]]; then
    msg_ok "Network configured ($ip)"
  else
    msg_warn "Container still has no IPv4 address on eth0"
  fi
}

# ------------------------------------------------------------------ conversion

pick_template_storage() {
  local candidates
  candidates=$(pvesm status --content vztmpl 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}')
  [[ -z "$candidates" ]] && candidates=$(pvesm status --content vztmpl 2>/dev/null | awk 'NR>1 {print $1}')
  echo "$candidates" | head -1
}

build_template() {
  local ref="$1"
  install_deps skopeo umoci jq

  msg_info "Pulling $ref"
  local -a auth=()
  mapfile -t auth < <(skopeo_auth_args)
  if ! skopeo copy --override-os linux --override-arch "$HOST_ARCH" \
    "${auth[@]/#--creds/--src-creds}" \
    "docker://$ref" "oci:$TMP_DIR/oci:converted" &>"$TMP_DIR/pull.log"; then
    msg_error "Pull failed"
    tail -20 "$TMP_DIR/pull.log" | sed 's/^/    /' >&2
    exit 1
  fi
  msg_ok "Pulled $ref"

  fetch_image_config "oci:$TMP_DIR/oci:converted" "$TMP_DIR/config.json"
  parse_image_config "$TMP_DIR/config.json"

  msg_info "Flattening layers"
  if ! umoci unpack --image "$TMP_DIR/oci:converted" "$TMP_DIR/bundle" &>"$TMP_DIR/unpack.log"; then
    msg_error "umoci unpack failed"
    tail -20 "$TMP_DIR/unpack.log" | sed 's/^/    /' >&2
    exit 1
  fi
  msg_ok "Layers flattened"

  ROOTFS="$TMP_DIR/bundle/rootfs"
  OSTYPE_DETECTED=$(detect_ostype "$ROOTFS")
  prepare_rootfs "$ROOTFS"

  local ext="tar.zst"
  have zstd || ext="tar.gz"
  local slug
  slug=$(echo "$ref" | sed 's|[/:]|-|g; s|[^a-zA-Z0-9._-]|-|g')
  TEMPLATE_VOLID="${TMPL_STORAGE}:vztmpl/oci-${slug}-${HOST_ARCH}.${ext}"
  if ! TEMPLATE_PATH=$(pvesm path "$TEMPLATE_VOLID" 2>/dev/null) || [[ -z "$TEMPLATE_PATH" ]]; then
    msg_error "Storage '$TMPL_STORAGE' cannot hold container templates (content type vztmpl)"
    exit 1
  fi
  mkdir -p "$(dirname "$TEMPLATE_PATH")"

  msg_info "Packing template"
  tar --numeric-owner --xattrs --xattrs-include='*' -caf "$TEMPLATE_PATH" -C "$ROOTFS" . 2>/dev/null ||
    tar --numeric-owner -caf "$TEMPLATE_PATH" -C "$ROOTFS" .
  msg_ok "Template created: $TEMPLATE_VOLID ($(du -h "$TEMPLATE_PATH" | cut -f1))"
}

build_net_arg() {
  local net="name=eth0,bridge=${BRIDGE}"
  [[ -n "${VLAN:-}" ]] && net+=",tag=${VLAN}"
  if [[ "$IP_MODE" == "static" ]]; then
    net+=",ip=${STATIC_IP}"
    [[ -n "${GATEWAY:-}" ]] && net+=",gw=${GATEWAY}"
  else
    net+=",ip=dhcp"
  fi
  echo "$net"
}

create_container_legacy() {
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
  if ! pct create "${args[@]}" &>"$TMP_DIR/create.log"; then
    msg_error "pct create failed"
    tail -30 "$TMP_DIR/create.log" | sed 's/^/    /' >&2
    exit 1
  fi
  CREATED_VMID="$VMID"
  msg_ok "Container $VMID created"

  if [[ "$INIT_STRATEGY" == "lxc.init" ]]; then
    local conf="/etc/pve/lxc/${VMID}.conf" a
    {
      printf 'lxc.init.cwd: %s\n' "${IMG_WORKDIR:-/}"
      printf 'lxc.init.cmd:'
      for a in "${IMG_ARGV[@]}"; do printf ' %s' "$a"; done
      printf '\n'
      for a in "${IMG_ENV[@]}" "${EXTRA_ENV_LIST[@]}"; do
        [[ "$a" == *=* ]] && printf 'lxc.environment: %s\n' "$a"
      done
    } >>"$conf"
    msg_ok "Raw lxc.init.cmd written to $conf"
  fi
}

create_container_native() {
  local -a args=(
    "$VMID"
    --hostname "$CT_NAME"
    --cores "$CORES"
    --memory "$MEMORY"
    --rootfs "${STORAGE}:${DISK},oci=${FULL_IMAGE}"
    --unprivileged "$UNPRIVILEGED"
    --nameserver "$DNS"
    --net0 "$(build_net_arg)"
  )
  [[ "$NESTING" == "1" ]] && args+=(--features nesting=1)

  msg_info "Creating container $VMID from OCI image (native)"
  if ! pct create "${args[@]}" &>"$TMP_DIR/create.log"; then
    msg_warn "Native OCI create failed - falling back to skopeo/umoci"
    tail -15 "$TMP_DIR/create.log" | sed 's/^/    /' >&2
    if pct status "$VMID" &>/dev/null; then
      msg_info "Removing partial container $VMID"
      pct destroy "$VMID" --force 1 --purge 1 &>/dev/null || true
    fi
    CONVERT_MODE="legacy"
    return 1
  fi
  CREATED_VMID="$VMID"
  msg_ok "Container $VMID created"

  local kv
  for kv in "${EXTRA_ENV_LIST[@]}"; do
    [[ "$kv" == *=* ]] || continue
    pct set "$VMID" -env "$kv" &>/dev/null || msg_warn "Could not set env $kv"
  done
  return 0
}

# ------------------------------------------------------------------ main flow

header_info
preflight
ensure_whiptail
TMP_DIR=$(mktemp -d)

CONVERT_MODE="${CONVERT_MODE:-auto}"
if [[ "$CONVERT_MODE" == "auto" ]]; then
  ((NATIVE_OCI)) && CONVERT_MODE="native" || CONVERT_MODE="legacy"
fi
if [[ "$CONVERT_MODE" == "native" ]] && ((!NATIVE_OCI)); then
  msg_warn "Native OCI support needs PVE 9.1+ (found $PVE_VER) - using legacy path"
  CONVERT_MODE="legacy"
fi

ask OCI_IMAGE "OCI/Docker image to convert\n(e.g. nginx:alpine, ghcr.io/user/app:1.2.3)" "nginx:alpine"
[[ -n "$OCI_IMAGE" ]] || {
  msg_error "No image specified"
  exit 1
}
FULL_IMAGE=$(normalize_image "$OCI_IMAGE")
msg_ok "Image: $FULL_IMAGE"

DEFAULT_NAME=$(echo "$OCI_IMAGE" | sed 's|.*/||; s/:.*//; s/[^a-zA-Z0-9-]/-/g' | cut -c1-60)
ask CT_NAME "Container hostname" "$DEFAULT_NAME"
ask VMID "Container ID" "$(pvesh get /cluster/nextid)"
ask CORES "CPU cores" "2"
ask MEMORY "Memory (MB)" "1024"
ask DISK "Disk size (GB)" "8"

DEFAULT_STORAGE=$(pvesm status --content rootdir 2>/dev/null | awk 'NR>1 && $3=="active" {print $1; exit}')
ask STORAGE "Storage for the container rootfs" "${DEFAULT_STORAGE:-local-lvm}"
ask TMPL_STORAGE "Storage for the generated template" "$(pick_template_storage)"
ask BRIDGE "Network bridge" "vmbr0"
ask VLAN "VLAN tag (empty for none)" ""
ask IP_MODE "IP mode: dhcp or static" "dhcp"

if [[ "$IP_MODE" == "static" ]]; then
  ask STATIC_IP "Static IP in CIDR notation (e.g. 192.168.1.50/24)" ""
  ask GATEWAY "Gateway" ""
  [[ -n "$STATIC_IP" ]] || {
    msg_error "Static mode selected but no IP given"
    exit 1
  }
fi
ask DNS "DNS server" "$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null || echo 1.1.1.1)"

if [[ -z "${UNPRIVILEGED:-}" ]]; then
  ask_yesno UNPRIV_ANSWER "Create as unprivileged container?\n\nRecommended. Some images need privileged mode." "yes"
  UNPRIVILEGED=$([[ "$UNPRIV_ANSWER" == "yes" ]] && echo 1 || echo 0)
fi
if [[ -z "${NESTING:-}" ]]; then
  ask_yesno NESTING_ANSWER "Enable the nesting feature?" "yes"
  NESTING=$([[ "$NESTING_ANSWER" == "yes" ]] && echo 1 || echo 0)
fi
ask_yesno START_AFTER "Start the container after creation?" "yes"

if [[ -n "${EXTRA_ENV:-}" ]]; then
  IFS=';' read -ra EXTRA_ENV_LIST <<<"$EXTRA_ENV"
else
  ask_yesno ADD_ENV_ANSWER "Add custom environment variables?" "no"
  if [[ "$ADD_ENV_ANSWER" == "yes" ]]; then
    while true; do
      CUSTOM_ENV=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Environment" \
        --inputbox "KEY=VALUE (empty to finish)" 9 70 "" 3>&1 1>&2 2>&3) || break
      [[ -z "$CUSTOM_ENV" ]] && break
      EXTRA_ENV_LIST+=("$CUSTOM_ENV")
    done
  fi
fi

header_info
echo -e "${YW}─────────────────────────────────────────────────────${CL}"
echo -e "${BL}Configuration${CL}"
echo -e "${YW}─────────────────────────────────────────────────────${CL}"
printf "  %-12s %s\n" "Image:" "$FULL_IMAGE"
printf "  %-12s %s\n" "Mode:" "$CONVERT_MODE ($([[ "$CONVERT_MODE" == native ]] && echo "pct oci=" || echo "skopeo+umoci"))"
printf "  %-12s %s\n" "ID / Name:" "$VMID / $CT_NAME"
printf "  %-12s %s\n" "Resources:" "${CORES} cores, ${MEMORY} MB, ${DISK} GB on $STORAGE"
printf "  %-12s %s\n" "Network:" "$BRIDGE ${VLAN:+vlan $VLAN }($IP_MODE${STATIC_IP:+ $STATIC_IP})"
printf "  %-12s %s\n" "Privileged:" "$([[ "$UNPRIVILEGED" == "1" ]] && echo no || echo yes)"
[[ ${#EXTRA_ENV_LIST[@]} -gt 0 ]] && printf "  %-12s %s\n" "Env vars:" "${#EXTRA_ENV_LIST[@]}"
echo -e "${YW}─────────────────────────────────────────────────────${CL}"
echo ""

if [[ "${ASSUME_YES:-0}" != "1" ]]; then
  whiptail --backtitle "Proxmox VE Helper Scripts" --title "Confirm" \
    --yesno "Create container $VMID from $FULL_IMAGE?" 9 70 || {
    msg_error "Cancelled by user"
    exit 0
  }
fi

if [[ "$CONVERT_MODE" == "native" ]]; then
  install_deps skopeo jq
  fetch_image_config "docker://$FULL_IMAGE" "$TMP_DIR/config.json"
  parse_image_config "$TMP_DIR/config.json"
  create_container_native || true
fi

if [[ "$CONVERT_MODE" == "legacy" ]]; then
  [[ -n "$TMPL_STORAGE" ]] || {
    msg_error "No storage with content type 'vztmpl' available"
    exit 1
  }
  build_template "$FULL_IMAGE"
  create_container_legacy
fi

if [[ "$START_AFTER" == "yes" ]]; then
  msg_info "Starting container"
  if pct start "$VMID" &>"$TMP_DIR/start.log"; then
    msg_ok "Container started"
    sleep 2
    bring_up_network "$VMID"
  else
    msg_error "Container failed to start"
    tail -20 "$TMP_DIR/start.log" | sed 's/^/    /' >&2
    echo -e " ${INFO} ${YW}Inspect with: pct start $VMID --debug${CL}"
  fi
fi

CT_IP="n/a"
if PID=$(container_pid "$VMID" 2>/dev/null); then
  CT_IP=$(netns_current_ipv4 "$PID")
  CT_IP="${CT_IP:-n/a}"
fi

echo ""
echo -e "${GN}─────────────────────────────────────────────────────${CL}"
echo -e "${BL}Container ready${CL}"
echo -e "${GN}─────────────────────────────────────────────────────${CL}"
printf "  %-10s %s\n" "ID:" "$VMID"
printf "  %-10s %s\n" "Name:" "$CT_NAME"
printf "  %-10s %s\n" "Image:" "$FULL_IMAGE"
printf "  %-10s %s\n" "IP:" "${CT_IP%%/*}"
[[ -n "${TEMPLATE_VOLID:-}" ]] && printf "  %-10s %s\n" "Template:" "$TEMPLATE_VOLID"
echo -e "${GN}─────────────────────────────────────────────────────${CL}"

if [[ ${#IMG_PORTS[@]} -gt 0 ]]; then
  echo -e " ${INFO} ${YW}Exposed ports:${CL} ${IMG_PORTS[*]}"
  [[ "${CT_IP}" != "n/a" ]] && echo -e " ${INFO} ${YW}Try:${CL} http://${CT_IP%%/*}:${IMG_PORTS[0]%%/*}"
fi
if [[ ${#IMG_VOLUMES[@]} -gt 0 ]]; then
  echo -e " ${WARN} ${YW}Image declares volumes:${CL} ${IMG_VOLUMES[*]}"
  echo -e "   ${YW}Persist them with:${CL} pct set $VMID -mp0 ${STORAGE}:8,mp=${IMG_VOLUMES[0]}"
fi
echo -e " ${INFO} ${YW}Console:${CL} pct console $VMID    ${YW}Shell:${CL} pct enter $VMID"
echo ""
