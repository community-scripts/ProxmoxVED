#!/usr/bin/env bash

# Copyright (c) 2026 community-scripts ORG
# Optional Proxmox VE LXC Guest Customization Hook Installer
# License: MIT
#
# Purpose:
#   Installs a host-side hookscript system for optional LXC guest customization.
#   The hookscript evaluates CT tags and optional config files, then installs
#   additional packages or applies optional shell/profile tuning inside the CT.
#
# Scope:
#   - LXC only
#   - opt-in
#   - tag/profile based
#   - idempotent
#   - separate from app install scripts
#
# Notes:
#   - Runs on the PVE host
#   - Executes customization inside containers via pct exec
#   - Intended as a generic post-provisioning/add-on layer

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
HOOKSCRIPT_FILE="/var/lib/vz/snippets/guest-customize.sh"
HOOKSCRIPT_VOLUME_ID="local:snippets/guest-customize.sh"
CONFIG_FILE="/etc/default/pve-auto-customize"
APPLICATOR_FILE="/usr/local/bin/pve-apply-guest-customize.sh"
PATH_UNIT_FILE="/etc/systemd/system/pve-auto-customize.path"
SERVICE_UNIT_FILE="/etc/systemd/system/pve-auto-customize.service"
README_FILE="/etc/pve-auto-customize/README"
EXAMPLE_OVERRIDE_FILE="/etc/pve-auto-customize/100.conf.example"

function header_info() {
  clear
  cat <<"EOF"
   ____ _   _ _____ ____ _____    ____ _   _ ____ _____ ___  __  __ ___ ___________
  / ___| | | | ____/ ___|_   _|  / ___| | | / ___|_   _/ _ \|  \/  |_ _|__  / ____|
 | |  _| | | |  _| \___ \ | |   | |   | | | \___ \ | || | | | |\/| || |  / /|  _|
 | |_| | |_| | |___ ___) || |   | |___| |_| |___) || || |_| | |  | || | / /_| |___
  \____|\___/|_____|____/ |_|    \____|\___/|____/ |_| \___/|_|  |_|___/____|_____|

EOF
}

YW=$'\033[33m'
GN=$'\033[1;92m'
RD=$'\033[01;31m'
BL=$'\033[1;34m'
CL=$'\033[m'
BFR=$'\r\033[K'
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

spinner() {
  local pid=$!
  local delay=0.1
  local spinstr='|/-\'
  while kill -0 "$pid" >/dev/null 2>&1; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep "$delay"
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

msg_info() {
  echo -ne " ${YW}›${CL}  $1..."
}

msg_ok() {
  echo -e "${BFR} ${CM}  $1"
}

msg_error() {
  echo -e "${BFR} ${CROSS}  $1"
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    msg_error "Please run this script as root"
    exit 1
  fi
}

require_pve() {
  if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "This script must be run on a Proxmox VE host"
    exit 1
  fi
}

print_usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Install or remove the Proxmox LXC guest customization hook system.

Options:
  --install       Install/update hookscript automation (default)
  --uninstall     Remove automation and cleanup hookscript assignments
  --status        Show current installation state
  --help, -h      Show this help message
EOF
}

create_directories() {
  msg_info "Creating required directories"
  mkdir -p /var/lib/vz/snippets
  mkdir -p /usr/local/bin
  mkdir -p /etc/default
  mkdir -p /etc/pve-auto-customize
  mkdir -p /var/lib/pve-auto-customize
  msg_ok "Created required directories"
}

create_main_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    msg_ok "Main configuration already exists, keeping existing file"
    return
  fi

  msg_info "Creating main configuration"
  cat <<'EOF' >"$CONFIG_FILE"
#
# Configuration for the Proxmox Automatic Guest Customization Hook
#
# This file is sourced by the host-side hookscript.
# Global defaults live here.
# Per-CT overrides can be placed under:
#   /etc/pve-auto-customize/<VMID>.conf
#
# -----------------------------------------------------------------------------
# GENERAL
# -----------------------------------------------------------------------------

# Space-separated CTIDs to skip entirely
IGNORE_IDS=""

# If set to 1, CT tags are evaluated (profile_*, pkg_*, feature_*).
# If set to 0, customization runs purely from config values below.
USE_TAGS=0

# If set to 1, customization will only run once per CT unless the marker is removed
RUN_ONCE=1

# If set to 1, customization will run on every start
# This overrides RUN_ONCE behavior conceptually, but use with caution
ALWAYS_RUN=0

# Marker directory used to prevent repeated execution
MARKER_DIR="/var/lib/pve-auto-customize"

# Enable verbose logging to journal/syslog-style stdout
VERBOSE=1

# Hook phase to execute customization in
# Recommended: post-start
HOOK_PHASE="post-start"

# Seconds to wait after post-start before attempting pct exec
POST_START_DELAY=8

# Retry behavior for pct exec / apt operations
RETRY_COUNT=20
RETRY_SLEEP=3

# -----------------------------------------------------------------------------
# APT / PACKAGE HANDLING
# -----------------------------------------------------------------------------

# Whether to run apt update before package installation
APT_UPDATE=1

# apt install options
APT_INSTALL_OPTS="-y --no-install-recommends"

# Optional cleanup after installs
APT_AUTOREMOVE=0
APT_CLEAN=1

# -----------------------------------------------------------------------------
# PROFILE DEFINITIONS
# -----------------------------------------------------------------------------
# Profiles are intentionally opinionated but optional.
# Assign them via CT tags, e.g.:
#   tags: profile_shell;profile_ops
#
# Supported tag formats:
#   profile_<name>
#   pkg_<name>
#
# Example:
#   profile_shell -> installs packages from PROFILE_shell_PACKAGES
#   pkg_fastfetch -> installs package "fastfetch"

PROFILE_shell_PACKAGES="bash-completion plocate"
PROFILE_ops_PACKAGES="curl wget unzip jq"
PROFILE_debug_PACKAGES="strace lsof procps"
PROFILE_files_PACKAGES="cifs-utils smbclient"
PROFILE_net_PACKAGES="dnsutils iputils-ping netcat-openbsd"

# Example disabled profile:
# PROFILE_dev_PACKAGES="git vim tmux"

# -----------------------------------------------------------------------------
# SHELL TUNING
# -----------------------------------------------------------------------------
# Enabled only when one of the following tags is present:
#   feature_shellrc
#   feature_fastfetch
#
# This is intentionally opt-in and not coupled to profiles automatically.

ENABLE_BASHRC_TUNING=1
ENABLE_BASH_COMPLETION_LINE=1
ENABLE_FASTFETCH_LINE=1

# Config-first feature toggles (work without tags)
ENABLE_SHELLRC_FEATURE=0
ENABLE_FASTFETCH_FEATURE=0

# If set to 1 and nala exists, apt/apt-get aliases will be added
ENABLE_NALA_ALIASES=0

# -----------------------------------------------------------------------------
# OPTIONAL FUTURE FEATURES (currently not implemented automatically)
# -----------------------------------------------------------------------------
# These are placeholders for future expansion.
#
# ENABLE_SERVICE_USER=0
# SERVICE_USER_NAME=""
#
# ENABLE_EXTERNAL_DB_BOOTSTRAP=0
# EXTERNAL_DB_TYPE=""
# EXTERNAL_DB_HOST=""
# EXTERNAL_DB_PORT=""
# EXTERNAL_DB_NAME=""
# EXTERNAL_DB_USER=""
# EXTERNAL_DB_PASSWORD=""
#
# ENABLE_ENV_FILE_TEMPLATING=0
# ENV_FILE_PATH=""
#
# ENABLE_FASTFETCH_CUSTOM_LOGO=0
# FASTFETCH_LOGO_PATH=""
#
EOF
  chmod 0644 "$CONFIG_FILE"
  msg_ok "Created main configuration"
}

create_example_override() {
  if [[ -f "$EXAMPLE_OVERRIDE_FILE" ]]; then
    msg_ok "Example per-CT override already exists, keeping existing file"
    return
  fi

  msg_info "Creating example per-CT override"
  cat <<'EOF' >"$EXAMPLE_OVERRIDE_FILE"
#
# Example per-CT override for CT 100
# Rename to:
#   /etc/pve-auto-customize/100.conf
#
# Only variables you define here will override global defaults.

# Example:
# RUN_ONCE=1
# APT_UPDATE=1
# POST_START_DELAY=10
#
# Add extra packages regardless of tags:
# EXTRA_PACKAGES="mc htop"
#
# Run without tags (recommended for normal users):
# USE_TAGS=0
# ENABLE_SHELLRC_FEATURE=1
# ENABLE_FASTFETCH_FEATURE=1
#
# Disable shellrc tuning for this CT:
# ENABLE_BASHRC_TUNING=0
#
# Force a local custom profile package definition:
# PROFILE_shell_PACKAGES="bash-completion plocate eza"
EOF
  chmod 0644 "$EXAMPLE_OVERRIDE_FILE"
  msg_ok "Created example per-CT override"
}

create_hookscript() {
  msg_info "Creating guest customization hookscript"
  cat <<'EOF' >"$HOOKSCRIPT_FILE"
#!/usr/bin/env bash
set -euo pipefail

VMID="${1:-}"
PHASE="${2:-}"

CONFIG_FILE="/etc/default/pve-auto-customize"

log() {
  echo "[hookscript-guest-customize] VMID ${VMID}: $1"
}

fail() {
  log "ERROR: $1"
  exit 1
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi

  local override="/etc/pve-auto-customize/${VMID}.conf"
  if [[ -f "$override" ]]; then
    # shellcheck disable=SC1090
    source "$override"
    log "Loaded per-CT override: $override"
  fi

  : "${IGNORE_IDS:=}"
  : "${USE_TAGS:=0}"
  : "${RUN_ONCE:=1}"
  : "${ALWAYS_RUN:=0}"
  : "${MARKER_DIR:=/var/lib/pve-auto-customize}"
  : "${VERBOSE:=1}"
  : "${HOOK_PHASE:=post-start}"
  : "${POST_START_DELAY:=8}"
  : "${RETRY_COUNT:=20}"
  : "${RETRY_SLEEP:=3}"
  : "${APT_UPDATE:=1}"
  : "${APT_INSTALL_OPTS:=-y --no-install-recommends}"
  : "${APT_AUTOREMOVE:=0}"
  : "${APT_CLEAN:=1}"
  : "${ENABLE_BASHRC_TUNING:=1}"
  : "${ENABLE_BASH_COMPLETION_LINE:=1}"
  : "${ENABLE_FASTFETCH_LINE:=1}"
  : "${ENABLE_SHELLRC_FEATURE:=0}"
  : "${ENABLE_FASTFETCH_FEATURE:=0}"
  : "${ENABLE_NALA_ALIASES:=0}"
  : "${PROFILE_shell_PACKAGES:=bash-completion plocate}"
  : "${PROFILE_ops_PACKAGES:=curl wget unzip jq}"
  : "${PROFILE_debug_PACKAGES:=strace lsof procps}"
  : "${PROFILE_files_PACKAGES:=cifs-utils smbclient}"
  : "${PROFILE_net_PACKAGES:=dnsutils iputils-ping netcat-openbsd}"
  : "${EXTRA_PACKAGES:=}"
}

is_ignored() {
  for ignored in $IGNORE_IDS; do
    [[ "$ignored" == "$VMID" ]] && return 0
  done
  return 1
}

ensure_lxc() {
  if ! pct config "$VMID" >/dev/null 2>&1; then
    log "Not an LXC or config not found. Skipping."
    exit 0
  fi
}

get_tags() {
  pct config "$VMID" | awk -F': ' '/^tags:/ {print $2}'
}

container_is_running() {
  pct status "$VMID" 2>/dev/null | grep -q '^status: running$'
}

retry_pct_exec() {
  local attempt=0
  while true; do
    if pct exec "$VMID" -- "$@"; then
      return 0
    fi

    attempt=$((attempt + 1))
    if (( attempt >= RETRY_COUNT )); then
      return 1
    fi

    sleep "$RETRY_SLEEP"
  done
}

append_unique_line_in_ct() {
  local target_file="$1"
  local line="$2"

  retry_pct_exec bash -c '
    target_file="$1"
    line="$2"
    touch "$target_file"
    grep -Fqx -- "$line" "$target_file" || echo "$line" >> "$target_file"
  ' _ "$target_file" "$line"
}

resolve_requested_packages() {
  local tags="$1"
  local pkgs=()
  local seen=""

  if [[ -n "$EXTRA_PACKAGES" ]]; then
    for pkg in $EXTRA_PACKAGES; do
      if [[ ! " $seen " =~ [[:space:]]$pkg[[:space:]] ]]; then
        pkgs+=("$pkg")
        seen+=" $pkg"
      fi
    done
  fi

  if [[ "$USE_TAGS" == "1" ]]; then
    local tag
    local tag_list="${tags//;/ }"
    for tag in $tag_list; do
      case "$tag" in
        profile_*)
          local profile="${tag#profile_}"
          local var="PROFILE_${profile}_PACKAGES"
          local profile_pkgs="${!var:-}"
          if [[ -n "$profile_pkgs" ]]; then
            for pkg in $profile_pkgs; do
              if [[ ! " $seen " =~ [[:space:]]$pkg[[:space:]] ]]; then
                pkgs+=("$pkg")
                seen+=" $pkg"
              fi
            done
          else
            log "Profile '$profile' has no package definition"
          fi
          ;;
        pkg_*)
          local pkg="${tag#pkg_}"
          if [[ -n "$pkg" ]] && [[ ! " $seen " =~ [[:space:]]$pkg[[:space:]] ]]; then
            pkgs+=("$pkg")
            seen+=" $pkg"
          fi
          ;;
      esac
    done
  fi

  printf '%s\n' "${pkgs[@]:-}"
}

run_apt_update_if_needed() {
  if [[ "$APT_UPDATE" == "1" ]]; then
    log "Running apt update"
    retry_pct_exec bash -c "export DEBIAN_FRONTEND=noninteractive; apt update"
  fi
}

is_valid_package_name() {
  local pkg="$1"
  [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9-]+)?$ ]]
}

install_packages() {
  local packages=("$@")
  local safe_packages=()
  local pkg

  if (( ${#packages[@]} == 0 )); then
    log "No packages requested"
    return 0
  fi

  for pkg in "${packages[@]}"; do
    if is_valid_package_name "$pkg"; then
      safe_packages+=("$pkg")
    else
      log "Skipping invalid package token: $pkg"
    fi
  done

  if (( ${#safe_packages[@]} == 0 )); then
    log "No valid packages left after validation"
    return 0
  fi

  log "Installing packages: ${safe_packages[*]}"
  retry_pct_exec bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt install $APT_INSTALL_OPTS ${safe_packages[*]}
  "
}

run_optional_cleanup() {
  if [[ "$APT_AUTOREMOVE" == "1" ]]; then
    log "Running apt autoremove"
    retry_pct_exec bash -c "export DEBIAN_FRONTEND=noninteractive; apt autoremove -y"
  fi

  if [[ "$APT_CLEAN" == "1" ]]; then
    log "Running apt clean"
    retry_pct_exec bash -c "apt clean"
  fi
}

apply_shellrc_features() {
  local tags="$1"
  local tag_list="${tags//;/ }"
  local enable_shellrc="$ENABLE_SHELLRC_FEATURE"
  local enable_fastfetch="$ENABLE_FASTFETCH_FEATURE"

  if [[ "$USE_TAGS" == "1" ]]; then
    local tag
    for tag in $tag_list; do
      case "$tag" in
        feature_shellrc) enable_shellrc=1 ;;
        feature_fastfetch) enable_fastfetch=1 ;;
      esac
    done
  fi

  if [[ "$ENABLE_BASHRC_TUNING" != "1" ]]; then
    log "Shellrc tuning globally disabled"
    return 0
  fi

  if [[ "$enable_shellrc" != "1" && "$enable_fastfetch" != "1" ]]; then
    log "No shell feature tags found"
    return 0
  fi

  log "Applying optional shellrc tuning"

  append_unique_line_in_ct "/root/.bashrc" ""
  append_unique_line_in_ct "/root/.bashrc" "# Added by pve-auto-customize"

  if [[ "$enable_shellrc" == "1" ]]; then
    append_unique_line_in_ct "/root/.bashrc" "export LS_OPTIONS='--color=auto'"
    append_unique_line_in_ct "/root/.bashrc" "eval \"\$(dircolors)\""
    append_unique_line_in_ct "/root/.bashrc" "alias ls='ls \$LS_OPTIONS -lA'"

    if [[ "$ENABLE_BASH_COMPLETION_LINE" == "1" ]]; then
      append_unique_line_in_ct "/root/.bashrc" "[ -f /usr/share/bash-completion/bash_completion ] && source /usr/share/bash-completion/bash_completion"
    fi

    if [[ "$ENABLE_NALA_ALIASES" == "1" ]]; then
      retry_pct_exec bash -c "command -v nala >/dev/null 2>&1" && {
        append_unique_line_in_ct "/root/.bashrc" "alias apt='nala'"
        append_unique_line_in_ct "/root/.bashrc" "alias apt-get='nala'"
      }
    fi
  fi

  if [[ "$enable_fastfetch" == "1" && "$ENABLE_FASTFETCH_LINE" == "1" ]]; then
    retry_pct_exec bash -c "command -v fastfetch >/dev/null 2>&1" && {
      append_unique_line_in_ct "/root/.bashrc" "fastfetch"
    }
  fi
}

write_marker() {
  mkdir -p "$MARKER_DIR"
  touch "${MARKER_DIR}/${VMID}.done"
}

marker_exists() {
  [[ -f "${MARKER_DIR}/${VMID}.done" ]]
}

main() {
  [[ -n "$VMID" ]] || fail "Missing VMID"
  [[ -n "$PHASE" ]] || fail "Missing phase"

  load_config
  ensure_lxc

  if [[ "$PHASE" != "$HOOK_PHASE" ]]; then
    log "Phase '$PHASE' does not match configured HOOK_PHASE '$HOOK_PHASE'. Skipping."
    exit 0
  fi

  if is_ignored; then
    log "CTID is ignored by config"
    exit 0
  fi

  if ! container_is_running; then
    log "Container not running yet. Skipping."
    exit 0
  fi

  if [[ "$HOOK_PHASE" == "post-start" ]] && [[ "$POST_START_DELAY" -gt 0 ]]; then
    sleep "$POST_START_DELAY"
  fi

  if [[ "$ALWAYS_RUN" != "1" && "$RUN_ONCE" == "1" ]] && marker_exists; then
    log "Marker exists. Customization already completed previously."
    exit 0
  fi

  local tags
  tags="$(get_tags)"
  local should_process=0
  if [[ -n "${EXTRA_PACKAGES:-}" ]]; then
    should_process=1
  fi
  if [[ "$ENABLE_SHELLRC_FEATURE" == "1" || "$ENABLE_FASTFETCH_FEATURE" == "1" ]]; then
    should_process=1
  fi
  if [[ "$USE_TAGS" == "1" && -n "$tags" ]]; then
    should_process=1
  fi

  if [[ "$should_process" != "1" ]]; then
    log "No active config/tags found. Nothing to do."
    if [[ "$RUN_ONCE" == "1" ]]; then
      write_marker
    fi
    exit 0
  fi

  log "--- Starting guest customization ---"
  [[ "$VERBOSE" == "1" ]] && log "USE_TAGS=$USE_TAGS, Tags: ${tags:-<none>}"

  local package_lines
  mapfile -t package_lines < <(resolve_requested_packages "$tags")
  local packages=()

  for line in "${package_lines[@]}"; do
    [[ -n "$line" ]] && packages+=("$line")
  done

  if (( ${#packages[@]} > 0 )); then
    run_apt_update_if_needed
    install_packages "${packages[@]}"
    run_optional_cleanup
  else
    log "Resolved package list is empty"
  fi

  apply_shellrc_features "$tags"

  if [[ "$RUN_ONCE" == "1" && "$ALWAYS_RUN" != "1" ]]; then
    write_marker
    log "Marker written"
  fi

  log "--- Guest customization complete ---"
}

main "$@"
EOF
  chmod +x "$HOOKSCRIPT_FILE"
  msg_ok "Created guest customization hookscript"
}

create_applicator_script() {
  msg_info "Creating hook applicator script"
  cat <<'EOF' >"$APPLICATOR_FILE"
#!/usr/bin/env bash
set -euo pipefail

HOOKSCRIPT_VOLUME_ID="local:snippets/guest-customize.sh"
CONFIG_FILE="/etc/default/pve-auto-customize"
LOG_TAG="pve-auto-customize"

log() {
  systemd-cat -t "$LOG_TAG" <<< "$1"
}

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

: "${IGNORE_IDS:=}"

is_ignored() {
  local vmid="$1"
  for ignored in $IGNORE_IDS; do
    [[ "$ignored" == "$vmid" ]] && return 0
  done
  return 1
}

pct list | awk 'NR>1 {print $1}' | while read -r CTID; do
  is_ignored "$CTID" && continue

  if pct config "$CTID" | grep -q '^hookscript:'; then
    current_hook="$(pct config "$CTID" | awk -F': ' '/^hookscript:/ {print $2}')"
    if [[ "$current_hook" == "$HOOKSCRIPT_VOLUME_ID" ]]; then
      continue
    fi

    log "CT $CTID already has another hookscript ($current_hook). Leaving unchanged"
    continue
  fi

  log "Applying hookscript to CT $CTID"
  pct set "$CTID" --hookscript "$HOOKSCRIPT_VOLUME_ID" >/dev/null 2>&1 || \
    log "Failed to apply hookscript to CT $CTID"
done
EOF
  chmod +x "$APPLICATOR_FILE"
  msg_ok "Created hook applicator script"
}

create_systemd_units() {
  msg_info "Creating systemd units"
  cat <<'EOF' >"$PATH_UNIT_FILE"
[Unit]
Description=Watch for new Proxmox LXC configs and apply guest customization hook

[Path]
PathExistsGlob=/etc/pve/lxc/*.conf
Unit=pve-auto-customize.service

[Install]
WantedBy=multi-user.target
EOF

  cat <<'EOF' >"$SERVICE_UNIT_FILE"
[Unit]
Description=Automatically add guest customization hookscript to LXCs

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pve-apply-guest-customize.sh
EOF
  chmod 0644 "$PATH_UNIT_FILE" "$SERVICE_UNIT_FILE"
  msg_ok "Created systemd units"
}

create_readme() {
  if [[ -f "$README_FILE" ]]; then
    msg_ok "Documentation already exists, keeping existing file"
    return
  fi

  msg_info "Creating documentation"
  cat <<'EOF' >"$README_FILE"
Proxmox Auto Guest Customize
============================

Overview
--------
This system applies a host-side hookscript to LXC containers.
On container start, the hookscript can optionally:

- install extra packages based on CT tags
- apply optional shellrc tuning
- honor global config and per-CT overrides
- run only once via marker files

Tag formats
-----------
Optional when USE_TAGS=1.

profile_<name>
  Uses PROFILE_<name>_PACKAGES from config

pkg_<package>
  Installs the specified package directly

feature_shellrc
  Enables optional root .bashrc tuning

feature_fastfetch
  Adds fastfetch to root .bashrc if installed

Examples
--------
Config-only (no tags):
Set USE_TAGS=0 and EXTRA_PACKAGES="fastfetch" in config or per-CT override.

tags: profile_shell;profile_ops
tags: pkg_fastfetch;pkg_jq
tags: profile_shell;pkg_fastfetch;feature_shellrc;feature_fastfetch

Global config
-------------
/etc/default/pve-auto-customize

Per-CT override
---------------
/etc/pve-auto-customize/<VMID>.conf

Marker files
------------
/var/lib/pve-auto-customize/<VMID>.done

Re-run customization for a CT
-----------------------------
Remove its marker file, e.g.

  rm -f /var/lib/pve-auto-customize/101.done

Then restart the CT.

Logs
----
journalctl -fu pve-auto-customize.service
journalctl -t pve-auto-customize -n 100
EOF
  chmod 0644 "$README_FILE"
  msg_ok "Created documentation"
}

enable_systemd() {
  msg_info "Reloading systemd and enabling watcher"
  (systemctl daemon-reload && systemctl enable --now pve-auto-customize.path) >/dev/null 2>&1 &
  spinner
  msg_ok "Enabled watcher"
}

initial_apply() {
  msg_info "Performing initial apply for existing LXCs"
  ("$APPLICATOR_FILE" >/dev/null 2>&1) &
  spinner
  msg_ok "Initial apply complete"
}

remove_hookscript_assignments() {
  msg_info "Removing hookscript assignment from LXCs using guest-customize"

  pct list | awk 'NR>1 {print $1}' | while read -r vmid; do
    current_hook="$(pct config "$vmid" | awk -F': ' '/^hookscript:/ {print $2}')"
    if [[ "$current_hook" == "$HOOKSCRIPT_VOLUME_ID" ]]; then
      pct set "$vmid" --delete hookscript >/dev/null 2>&1 && msg_ok "Removed hookscript from LXC $vmid"
    fi
  done
}

print_status() {
  local installed="no"
  local watcher_state="inactive"

  [[ -f "$HOOKSCRIPT_FILE" ]] && installed="yes"
  if systemctl is-active --quiet pve-auto-customize.path; then
    watcher_state="active"
  fi

  echo
  echo "pve-auto-customize status"
  echo "-------------------------"
  echo "Hookscript file:     $installed"
  echo "Path watcher state:  $watcher_state"
  echo "Config file:         $CONFIG_FILE"
  echo "Applicator file:     $APPLICATOR_FILE"
  echo
}

install_stack() {
  create_directories
  create_main_config
  create_example_override
  create_hookscript
  create_applicator_script
  create_systemd_units
  create_readme
  enable_systemd
  initial_apply
  print_summary
}

uninstall_stack() {
  remove_hookscript_assignments

  msg_info "Stopping and disabling systemd units"
  systemctl disable --now pve-auto-customize.path >/dev/null 2>&1 || true
  systemctl disable --now pve-auto-customize.service >/dev/null 2>&1 || true

  msg_info "Removing installed files"
  rm -f "$HOOKSCRIPT_FILE" "$APPLICATOR_FILE" "$PATH_UNIT_FILE" "$SERVICE_UNIT_FILE"

  if systemctl daemon-reload >/dev/null 2>&1; then
    msg_ok "systemd daemon reloaded"
  else
    msg_error "Failed to reload systemd daemon"
  fi

  msg_ok "Uninstall complete"
}

print_summary() {
  echo
  echo -e "${GN}Installation successful!${CL}"
  echo
  echo -e "${BL}Files created:${CL}"
  echo "  /var/lib/vz/snippets/guest-customize.sh"
  echo "  /usr/local/bin/pve-apply-guest-customize.sh"
  echo "  /etc/default/pve-auto-customize"
  echo "  /etc/pve-auto-customize/100.conf.example"
  echo "  /etc/pve-auto-customize/README"
  echo "  /etc/systemd/system/pve-auto-customize.path"
  echo "  /etc/systemd/system/pve-auto-customize.service"
  echo
  echo -e "${BL}Next steps:${CL}"
  echo "  1. Edit /etc/default/pve-auto-customize (or /etc/pve-auto-customize/<VMID>.conf)"
  echo "  2. For simple usage without tags: set USE_TAGS=0 and EXTRA_PACKAGES='fastfetch'"
  echo "  3. Optional tag mode: USE_TAGS=1 and set CT tags (profile_*/pkg_*/feature_*)"
  echo "  4. Restart the CT"
  echo
  echo -e "${BL}Useful commands:${CL}"
  echo "  pct config 101"
  echo "  rm -f /var/lib/pve-auto-customize/101.done"
  echo "  journalctl -fu pve-auto-customize.service"
  echo "  journalctl -t pve-auto-customize -n 100"
  echo
}

main() {
  header_info
  require_root
  require_pve

  local mode="install"
  case "${1:-}" in
  "" | --install)
    mode="install"
    ;;
  --uninstall)
    mode="uninstall"
    ;;
  --status)
    print_status
    exit 0
    ;;
  --help | -h)
    print_usage
    exit 0
    ;;
  *)
    msg_error "Unknown option: $1"
    print_usage
    exit 1
    ;;
  esac

  if [[ "$mode" == "install" ]]; then
    echo -e "\nThis script will install an optional LXC guest customization framework on this Proxmox VE host."
    echo -e "It will create/update files in:"
    echo -e "  - /var/lib/vz/snippets/"
    echo -e "  - /usr/local/bin/"
    echo -e "  - /etc/default/"
    echo -e "  - /etc/pve-auto-customize/"
    echo -e "  - /etc/systemd/system/\n"
  else
    echo -e "\nThis will uninstall the pve-auto-customize automation and remove managed files."
    echo -e "Existing CT hookscript assignments pointing to guest-customize will be removed.\n"
  fi

  read -r -p "Do you want to proceed? (y/n): " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    msg_error "Operation cancelled"
    exit 1
  fi

  echo

  if [[ "$mode" == "install" ]]; then
    install_stack
  else
    uninstall_stack
  fi
}

main "$@"
