#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Mihael Zamin Sousa (mihazs)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://openwrt.org/

APP="OpenWrt"
var_tags="${var_tags:-os;router;network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-openwrt}"
var_version="${var_version:-25.12}"
var_unprivileged="${var_unprivileged:-1}"

var_arm64="${var_arm64:-no}"
var_tun="${var_tun:-yes}"
var_lan_bridge="${var_lan_bridge:-vmbr0}"
var_wan_bridge="${var_wan_bridge:-vmbr0}"
var_allow_same_bridge="${var_allow_same_bridge:-no}"
var_lan_ipaddr="${var_lan_ipaddr:-192.168.1.1}"
var_lan_netmask="${var_lan_netmask:-255.255.255.0}"
var_interface="${var_interface:-yes}"
var_interface_packages="${var_interface_packages:-luci}"

OPENWRT_TEMPLATE_INDEX_URL="https://images.linuxcontainers.org/meta/1.0/index-system"
OPENWRT_INSTALL_FALLBACK_URL="${OPENWRT_INSTALL_FALLBACK_URL:-https://raw.githubusercontent.com/mihazs/ProxmoxVED/add-openwrt-lxc}"

function openwrt_fetch_template_index() {
  curl -fsSL --connect-timeout 10 --max-time 30 "$OPENWRT_TEMPLATE_INDEX_URL" 2>/dev/null ||
    curl -4 -fsSL --connect-timeout 10 --max-time 30 "$OPENWRT_TEMPLATE_INDEX_URL" 2>/dev/null
}

function openwrt_normalize_release() {
  local requested="${1:-latest}"
  case "$requested" in
  "" | latest | stable) echo "latest" ;;
  snapshot) echo "snapshot" ;;
  [0-9]*.[0-9]*.[0-9]*) echo "${requested%.*}" ;;
  *) echo "$requested" ;;
  esac
}

function openwrt_latest_stable_release() {
  awk -F';' '$1 == "openwrt" && $2 != "snapshot" { print $2 }' | sort -uV | tail -n1
}

function openwrt_lxc_arch() {
  local arch
  arch="$(dpkg --print-architecture)"
  case "$arch" in
  amd64 | arm64) echo "$arch" ;;
  *) return 1 ;;
  esac
}

function openwrt_resolve_template() {
  local lxc_arch index requested_release release line template_path build_id

  lxc_arch="$(openwrt_lxc_arch)" || {
    msg_error "No OpenWrt LinuxContainers template mapping for architecture $(dpkg --print-architecture)"
    return 207
  }

  index="$(openwrt_fetch_template_index)" || {
    msg_error "Failed to read OpenWrt LinuxContainers template index"
    return 222
  }

  requested_release="$(openwrt_normalize_release "${PCT_OSVERSION:-${var_version:-latest}}")"
  if [[ "$requested_release" == "latest" ]]; then
    release="$(printf "%s\n" "$index" | openwrt_latest_stable_release)"
  else
    release="$requested_release"
  fi

  [[ -n "$release" ]] || {
    msg_error "No stable OpenWrt release found in LinuxContainers index"
    return 225
  }

  line="$(awk -F';' -v release="$release" -v arch="$lxc_arch" '$1 == "openwrt" && $2 == release && $3 == arch && $4 == "default" { selected = $0 } END { print selected }' <<<"$index")"
  [[ -n "$line" ]] || {
    msg_error "No OpenWrt ${release} ${lxc_arch} template found in LinuxContainers index"
    return 225
  }

  var_version="$release"
  PCT_OSVERSION="$release"
  export var_version PCT_OSVERSION

  template_path="$(awk -F';' '{ print $6 }' <<<"$line")"
  build_id="$(awk -F';' '{ print $5 }' <<<"$line" | tr ':/' '--')"
  TEMPLATE="openwrt-${release}-${lxc_arch}-${build_id}-rootfs.tar.xz"
  OPENWRT_TEMPLATE_URL="https://images.linuxcontainers.org${template_path}rootfs.tar.xz"
  export TEMPLATE OPENWRT_TEMPLATE_URL
}

function preflight_template_connectivity() {
  if openwrt_fetch_template_index >/dev/null; then
    preflight_pass "Template server reachable (images.linuxcontainers.org)"
  else
    preflight_fail "LinuxContainers template index unreachable" 222
    echo -e "    ${TAB}${INFO} Check internet connectivity or manually upload the OpenWrt rootfs template"
  fi
}

function preflight_template_available() {
  if openwrt_resolve_template; then
    preflight_pass "Template available online for OpenWrt ${var_version} ($(openwrt_lxc_arch))"
  else
    preflight_fail "OpenWrt LinuxContainers template unavailable" 225
  fi
}

function openwrt_template_path() {
  local template_path template_base

  template_path="$(pvesm path "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" 2>/dev/null || true)"
  if [[ -n "$template_path" ]]; then
    echo "$template_path"
    return 0
  fi

  template_base="$(awk -v storage="$TEMPLATE_STORAGE" '
    $0 ~ "^[^:]+:[[:space:]]*" storage "$" { found = 1; next }
    found && /^[^[:space:]]/ { found = 0 }
    found && $1 == "path" { print $2; exit }
  ' /etc/pve/storage.cfg)"
  [[ -n "$template_base" ]] || {
    msg_error "Could not resolve OpenWrt template path for storage ${TEMPLATE_STORAGE}."
    return 213
  }
  echo "${template_base}/template/cache/${TEMPLATE}"
}

function openwrt_download_template() {
  local template_path="$1"

  mkdir -p "$(dirname "$template_path")" || {
    msg_error "Cannot create OpenWrt template directory."
    exit 207
  }

  msg_info "Downloading OpenWrt rootfs template"
  curl -fsSL -o "$template_path" "$OPENWRT_TEMPLATE_URL" || {
    msg_error "Failed to download OpenWrt template from: $OPENWRT_TEMPLATE_URL"
    exit 222
  }
  msg_ok "Downloaded OpenWrt LXC template"
}

function openwrt_prepare_template() {
  if [[ -z "${TEMPLATE:-}" || -z "${OPENWRT_TEMPLATE_URL:-}" ]]; then
    openwrt_resolve_template || exit $?
  fi

  TEMPLATE_PATH="$(openwrt_template_path)" || exit $?
  export TEMPLATE_PATH

  if [[ ! -f "$TEMPLATE_PATH" ]]; then
    openwrt_download_template "$TEMPLATE_PATH"
  elif ! tar -tf "$TEMPLATE_PATH" &>/dev/null; then
    msg_warn "Local OpenWrt template is not a readable tar archive; re-downloading."
    rm -f "$TEMPLATE_PATH"
    openwrt_download_template "$TEMPLATE_PATH"
  else
    msg_ok "Template ${BL}${TEMPLATE}${CL} found locally."
  fi
}

function openwrt_net_option() {
  local bridge="$1" ip_mode="$2" vlan="$3" mtu="$4" options=""

  if [[ -n "$vlan" ]]; then
    case "$vlan" in
    ,tag=*) options+="$vlan" ;;
    *) options+=",tag=$vlan" ;;
    esac
  fi

  if [[ -n "$mtu" ]]; then
    case "$mtu" in
    ,mtu=*) options+="$mtu" ;;
    *) options+=",mtu=$mtu" ;;
    esac
  fi

  echo "bridge=${bridge},ip=${ip_mode}${options}"
}

function openwrt_validate_network_bridges() {
  local lan_bridge="$1" wan_bridge="$2"

  if [[ "$lan_bridge" != "$wan_bridge" ]]; then
    return 0
  fi

  case "${var_allow_same_bridge:-no}" in
  yes | true | 1 | on)
    msg_warn "OpenWrt LAN and WAN both use bridge ${lan_bridge}; continuing because var_allow_same_bridge is enabled."
    ;;
  *)
    msg_error "OpenWrt LAN and WAN bridges are both set to ${lan_bridge}. Set var_lan_bridge and var_wan_bridge to different bridges, or set var_allow_same_bridge=yes after reviewing the topology."
    exit 1
    ;;
  esac
}

function openwrt_fetch_install_script() {
  local primary_url fallback_url install_url fetched_script failed_urls=()

  primary_url="${COMMUNITY_SCRIPTS_URL%/}/install/${var_install:?}.sh"
  fallback_url="${OPENWRT_INSTALL_FALLBACK_URL%/}/install/${var_install:?}.sh"

  for install_url in "$primary_url" "$fallback_url"; do
    [[ "$install_url" == "$primary_url" && "${#failed_urls[@]}" -gt 0 ]] && continue
    if fetched_script="$(curl -fsSL "$install_url" 2>/dev/null)" && [[ -n "$fetched_script" ]]; then
      OPENWRT_INSTALL_SCRIPT="$fetched_script"
      return 0
    fi
    failed_urls+=("$install_url")
  done

  for install_url in "${failed_urls[@]}"; do
    msg_warn "Unavailable OpenWrt install script: ${install_url}"
  done
  msg_error "Failed to download OpenWrt install script"
  return 222
}

function openwrt_select_storages() {
  check_storage_support "rootdir" || {
    msg_error "No valid storage found for 'rootdir' [Container]"
    exit 1
  }
  check_storage_support "vztmpl" || {
    msg_error "No valid storage found for 'vztmpl' [Template]"
    exit 1
  }

  if resolve_storage_preselect template "${TEMPLATE_STORAGE:-${var_template_storage:-}}"; then
    TEMPLATE_STORAGE="$STORAGE_RESULT"
    TEMPLATE_STORAGE_INFO="$STORAGE_INFO"
    msg_ok "Storage ${BL}${TEMPLATE_STORAGE}${CL} (${TEMPLATE_STORAGE_INFO}) [Template]"
  else
    select_storage template
    TEMPLATE_STORAGE="$STORAGE_RESULT"
    TEMPLATE_STORAGE_INFO="$STORAGE_INFO"
    msg_ok "Storage ${BL}${TEMPLATE_STORAGE}${CL} (${TEMPLATE_STORAGE_INFO}) [Template]"
  fi

  if resolve_storage_preselect container "${CONTAINER_STORAGE:-${var_container_storage:-}}"; then
    CONTAINER_STORAGE="$STORAGE_RESULT"
    CONTAINER_STORAGE_INFO="$STORAGE_INFO"
    msg_ok "Storage ${BL}${CONTAINER_STORAGE}${CL} (${CONTAINER_STORAGE_INFO}) [Container]"
  else
    select_storage container
    CONTAINER_STORAGE="$STORAGE_RESULT"
    CONTAINER_STORAGE_INFO="$STORAGE_INFO"
    msg_ok "Storage ${BL}${CONTAINER_STORAGE}${CL} (${CONTAINER_STORAGE_INFO}) [Container]"
  fi

  validate_storage_space "$CONTAINER_STORAGE" "$DISK_SIZE" "yes" || true
}

function openwrt_build_pct_options() {
  local lan_bridge="${var_lan_bridge:-${BRG:-vmbr0}}"
  local wan_bridge="${var_wan_bridge:-${BRG:-vmbr0}}"
  local lan_vlan="${var_lan_vlan:-}"
  local wan_vlan="${var_wan_vlan:-${VLAN:-}}"
  local openwrt_mtu="${var_openwrt_mtu:-${MTU:-}}"
  local features=""
  local extra_options=()

  openwrt_validate_network_bridges "$lan_bridge" "$wan_bridge"

  if [[ "${ENABLE_NESTING:-1}" == "1" ]]; then
    features="nesting=1"
  fi
  if [[ "${CT_TYPE:?}" == "1" ]]; then
    [[ -n "$features" ]] && features+=","
    features+="keyctl=1"
  fi
  if [[ "$ENABLE_FUSE" == "yes" ]]; then
    [[ -n "$features" ]] && features+=","
    features+="fuse=1"
  fi

  OPENWRT_PCT_ARGS=()
  if [[ -n "$features" ]]; then
    OPENWRT_PCT_ARGS+=(-features "$features")
  fi
  OPENWRT_PCT_ARGS+=(-hostname "$HN")
  if [[ -n "$TAGS" ]]; then
    OPENWRT_PCT_ARGS+=(-tags "$TAGS")
  fi
  if [[ -n "$SD" ]]; then
    read -r -a extra_options <<<"$SD"
    OPENWRT_PCT_ARGS+=("${extra_options[@]}")
  fi
  if [[ -n "$NS" ]]; then
    read -r -a extra_options <<<"$NS"
    OPENWRT_PCT_ARGS+=("${extra_options[@]}")
  fi

  OPENWRT_PCT_ARGS+=(
    -net0 "name=eth0,$(openwrt_net_option "$lan_bridge" manual "$lan_vlan" "$openwrt_mtu")"
    -net1 "name=eth1,$(openwrt_net_option "$wan_bridge" dhcp "$wan_vlan" "$openwrt_mtu")"
    -onboot 1
    -cores "$CORE_COUNT"
    -memory "$RAM_SIZE"
    -unprivileged "${CT_TYPE:?}"
    -ostype unmanaged
    -rootfs "$CONTAINER_STORAGE:${DISK_SIZE}"
  )

  if [[ "${PROTECT_CT:-}" == "1" || "${PROTECT_CT:-}" == "yes" ]]; then
    OPENWRT_PCT_ARGS+=(-protection 1)
  fi
  if [[ -n "${CT_TIMEZONE:-}" ]]; then
    OPENWRT_PCT_ARGS+=(-timezone "$CT_TIMEZONE")
  fi
  if [[ -n "$PW" ]]; then
    read -r -a extra_options <<<"$PW"
    OPENWRT_PCT_ARGS+=("${extra_options[@]}")
  fi
}

function openwrt_create_lxc() {
  local logfile lockfile

  [[ "$CTID" -ge 100 ]] || {
    msg_error "ID cannot be less than 100."
    exit 205
  }
  if qm status "$CTID" &>/dev/null || pct status "$CTID" &>/dev/null; then
    echo -e "ID '$CTID' is already in use."
    msg_error "Cannot use ID that is already in use."
    exit 206
  fi

  openwrt_select_storages
  lockfile="/tmp/template.openwrt.lock"
  exec 9>"$lockfile" || {
    msg_error "Failed to create lock file '$lockfile'."
    exit 200
  }
  flock -w 300 9 || {
    msg_error "Timeout while waiting for template lock."
    exit 211
  }

  openwrt_resolve_template || exit $?
  openwrt_prepare_template
  openwrt_build_pct_options

  logfile="/tmp/pct_create_${CTID}_$(date +%Y%m%d_%H%M%S)_${SESSION_ID}.log"
  LOGFILE="$logfile"
  export LOGFILE

  msg_info "Creating LXC container"
  grep -q "root:100000:65536" /etc/subuid || echo "root:100000:65536" >>/etc/subuid
  grep -q "root:100000:65536" /etc/subgid || echo "root:100000:65536" >>/etc/subgid

  if ! pct create "$CTID" "$TEMPLATE_PATH" "${OPENWRT_PCT_ARGS[@]}" >"$logfile" 2>&1; then
    if grep -qiE 'unable to open|corrupt|invalid' "$logfile"; then
      msg_warn "Template appears invalid; re-downloading."
      rm -f "$TEMPLATE_PATH"
      openwrt_download_template "$TEMPLATE_PATH"
      pct create "$CTID" "$TEMPLATE_PATH" "${OPENWRT_PCT_ARGS[@]}" >>"$logfile" 2>&1 || {
        msg_error "Container creation failed. See $logfile"
        exit 209
      }
    else
      msg_error "Container creation failed. See $logfile"
      exit 209
    fi
  fi

  exec 9>&-
  pct list | awk '{ print $1 }' | grep -qx "$CTID" || {
    msg_error "Container ID $CTID not listed in 'pct list'. See $logfile"
    exit 215
  }
  msg_ok "LXC Container ${BL}${CTID}${CL} ${GN}was successfully created."
}

function openwrt_configure_devices() {
  LXC_CONFIG="/etc/pve/lxc/${CTID}.conf"
  export LXC_CONFIG

  if [[ "$ENABLE_TUN" == "yes" ]]; then
    cat <<EOF >>"$LXC_CONFIG"
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
EOF
  fi
}

function openwrt_run_install_script() {
  local install_script lxc_exit install_exit_code=0 error_flag

  export OPENWRT_INTERFACE="${var_interface:-yes}"
  export OPENWRT_INTERFACE_PACKAGES="${var_interface_packages:-luci}"
  export OPENWRT_LAN_IPADDR="${var_lan_ipaddr:-192.168.1.1}"
  export OPENWRT_LAN_NETMASK="${var_lan_netmask:-255.255.255.0}"

  start_install_timer
  openwrt_fetch_install_script || {
    install_exit_code=$?
    post_update_to_api "failed" "$install_exit_code"
    exit "$install_exit_code"
  }
  install_script="$OPENWRT_INSTALL_SCRIPT"

  set +Eeuo pipefail
  trap - ERR
  lxc-attach -n "$CTID" -- /bin/ash -c "$install_script"
  lxc_exit=$?
  set -Eeuo pipefail
  trap 'error_handler' ERR

  if [[ -n "${SESSION_ID:-}" ]]; then
    error_flag="/root/.install-${SESSION_ID}.failed"
    if pct exec "$CTID" -- test -f "$error_flag" 2>/dev/null; then
      install_exit_code="$(pct exec "$CTID" -- cat "$error_flag" 2>/dev/null || echo "1")"
      pct exec "$CTID" -- rm -f "$error_flag" 2>/dev/null || true
    fi
  fi
  if [[ "$install_exit_code" -eq 0 && "$lxc_exit" -ne 0 ]]; then
    install_exit_code="$lxc_exit"
  fi
  if [[ "$install_exit_code" -ne 0 ]]; then
    msg_error "Installation failed in container ${CTID} (exit code: ${install_exit_code})"
    post_update_to_api "failed" "$install_exit_code"
    exit "$install_exit_code"
  fi
}

function openwrt_build_container() {
  TEMP_DIR="$(mktemp -d)"
  pushd "$TEMP_DIR" >/dev/null

  export DIAGNOSTICS="$DIAGNOSTICS"
  export RANDOM_UUID="$RANDOM_UUID"
  export EXECUTION_ID="$EXECUTION_ID"
  export SESSION_ID="$SESSION_ID"
  export CACHER="$APT_CACHER"
  export CACHER_IP="$APT_CACHER_IP"
  export tz="${timezone:-}"
  export APPLICATION="$APP"
  export app="$NSAPP"
  export PASSWORD="$PW"
  export VERBOSE="$VERBOSE"
  export SSH_ROOT="${SSH}"
  export SSH_AUTHORIZED_KEY
  export CTID="${CT_ID:?}"
  export CTTYPE="${CT_TYPE:?}"
  export ENABLE_FUSE="$ENABLE_FUSE"
  export ENABLE_TUN="$ENABLE_TUN"
  export PCT_OSTYPE="$var_os"
  export PCT_OSVERSION="$var_version"
  export PCT_DISK_SIZE="$DISK_SIZE"
  export IPV6_METHOD="$IPV6_METHOD"
  export ENABLE_GPU="$ENABLE_GPU"
  export APPLICATION_VERSION="${var_appversion:-}"
  export BUILD_LOG="$BUILD_LOG"
  export INSTALL_LOG="/root/.install-${SESSION_ID}.log"
  export COMMUNITY_SCRIPTS_URL="$COMMUNITY_SCRIPTS_URL"
  export MODE="${METHOD:-default}"

  _HOST_LOGFILE="$BUILD_LOG"
  export _HOST_LOGFILE

  post_to_api
  post_progress_to_api "validation"
  openwrt_create_lxc
  post_progress_to_api "configuring"
  openwrt_configure_devices

  msg_info "Starting LXC Container"
  pct start "$CTID"
  for i in {1..10}; do
    if pct status "$CTID" | grep -q "status: running"; then
      msg_ok "Started LXC Container"
      break
    fi
    sleep 1
    if [[ "$i" -eq 10 ]]; then
      msg_error "LXC Container did not reach running state"
      exit 1
    fi
  done

  msg_info "Customizing LXC Container"
  sleep 3
  msg_ok "Customized LXC Container"

  install_ssh_keys_into_ct
  openwrt_run_install_script
  rm -f "/tmp/.install-capture-${SESSION_ID}.log" 2>/dev/null

  popd >/dev/null
  rm -rf "$TEMP_DIR"
}

function build_container() { openwrt_build_container; }

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  msg_error "Automated OpenWrt LXC upgrades are not supported. Use OpenWrt's sysupgrade process after reviewing container networking and package compatibility."
  exit
}

start
build_container
description
IP="${IP:-${var_lan_ipaddr:-192.168.1.1}}"

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
