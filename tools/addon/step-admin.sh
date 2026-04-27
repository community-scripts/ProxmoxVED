#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://smallstep.com/ | Github: https://github.com/smallstep

# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/error_handler.func)

# ==============================================================================
# Enable error handling
#
# set -E (enable errtrace option)
# set -e (enable errexit option)
# set -u (enable nounset option)
# set -o pipefail
# ==============================================================================
set -Eeuo pipefail
#trap 'error_handler' ERR

shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR

function error_exit() {
  trap - ERR
  local reason="Unknown failure occured!"
  local msg="${1:-$reason}"
  msg_error "ERROR $EXIT at line $LINE: ${YW}$msg${CL}" 1>&2
  exit "$EXIT"
}

# ==============================================================================
# CONFIGURATION VARIABLES
# Set these variables to skip interactive prompts (Whiptail dialogs)
# ==============================================================================
# VERBOSE: Set default verbose mode (no = silent) for script execution
#   Options: "yes" | "no" | "" (empty = silent)
VERBOSE="${VERBOSE:-}"

# var_unattended: Run without user interaction
#   Options: "yes" | "no" | "" (empty = interactive prompt)
var_unattended="${var_unattended:-}"

# var_action: Skip initial dialog and directly perform an maintenance option
#   Options: "install" | "update" | "uninstall" | "maintain" | "export-config" | "" (default: empty = interactive prompt)
var_action="${var_action:-}"

# var_cert_type: Skip dialog and directly maintain selected certificate type
#   Options: "x509" | "ssh" | "ca" | "" (default: empty = interactive prompt)
var_cert_type="${var_cert_type:-}"

# var_x509_action: Skip dialog and directly perform an maintenance option for x509 certificates
#   Options: "bootstrap" | "request" | "renew" | "revoke" | "inspect" | "list" | "crl" | "" (default: empty = interactive prompt)
var_x509_action="${var_x509_action:-}"

# ==============================================================================
# JSON CONFIG EXPORT
# Run with --export-config to output current configuration as JSON
# ==============================================================================
function export_config_json() {
  init_app
  cat <<EOF
{
  "VERBOSE": "${VERBOSE}",
  "var_unattended": "${var_unattended}",
  "var_action": "${var_action}",
  "var_cert_type": "${var_cert_type}",
  "var_x509_action": "${var_x509_action}",
  "APP": "${APP}",
  "APP_TYPE": "${APP_TYPE}",
  "APP_TITLE": "${APP_TITLE}",
  "APP_BACKTITLE": "${APP_BACKTITLE}",
  "BINARY_PATH": "${BINARY_PATH}",
  "CONFIG_PATH": "${CONFIG_PATH}",
  "STEPHOME": "${STEPHOME}",
  "STEPPATH": "${STEPPATH}",
  "CERT_PATH": "${CERT_PATH}",
  "KEY_PATH": "${KEY_PATH}",
  "SYS_CA_PATH": "${SYS_CA_PATH}",
  "CA_PATH": "${CA_PATH}",
  "CA_CONFIG": "${CA_CONFIG}",
  "CA_DEFAULTS": "${CA_DEFAULTS}",
  "CA_FINGERPRINT": "${CA_FINGERPRINT}",
  "CA_ORG": "${CA_ORG}",
  "CA_CN": "${CA_CN}",
  "CA_CN_ROOT": "${CA_CN_ROOT}",
  "CA_CN_CRT": "${CA_CN_CRT}",
  "CA_VALIDITY_ROOT": "${CA_VALIDITY_ROOT}",
  "CA_VALIDITY_CRT": "${CA_VALIDITY_CRT}",
  "CA_SERIAL_ROOT": "${CA_SERIAL_ROOT}",
  "CA_SERIAL_CRT": "${CA_SERIAL_CRT}",
  "CA_FQDN": "${CA_FQDN}",
  "CA_URL": "${CA_URL}",
  "CA_URL_ROOT": "${CA_URL_ROOT}",
  "CA_URL_CRT": "${CA_URL_CRT}",
  "CA_URL_CRL": "${CA_URL_CRL}",
  "CA_ROOT": "${CA_ROOT}",
  "CA_ROOT_KEY": "${CA_ROOT_KEY}",
  "CA_CRT": "${CA_CRT}",
  "CA_CRT_KEY": "${CA_CRT_KEY}",
  "CA_TEMPLATE_CRT": "${CA_TEMPLATE_CRT}",
  "CA_TEMPLATE_X509": "${CA_TEMPLATE_X509}",
  "CA_PROVISIONER": "${CA_PROVISIONER}",
  "CA_PROVISIONER_TYPE": "${CA_PROVISIONER_TYPE}",
  "CA_PROVISIONER_PWD_FILE": "${CA_PROVISIONER_PWD_FILE}"
}
EOF
}

# ==============================================================================
# USAGE
# Run with --help to output the script usage
# ==============================================================================
function print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Maintain certificate(s) issued by a Step certificate authority.

Options:
  --help              Show this help message
  --export-config     Export current Configuration as JSON

Environment Variables:

  VERBOSE             Run in verbose mode (yes/no); no for silent script execution
  var_unattended      Run without user interaction (yes/no)
  var_action          Skip initial dialog and directly perform an maintenance option (install/update/uninstall/maintain/export-config)
  var_cert_type       Skip dialog and directly maintain selected certificate type (x509/ssh/ca)
  var_x509_action     Skip dialog and directly perform an maintenance option for x509 certificates (bootstrap/request/renew/revoke/inspect/list/crl)

Examples:
  # Run interactively
  $(basename "$0")

  # Install unattended
  var_unattended=yes var_action=install $(basename "$0")

  # Update unattended
  var_unattended=yes var_action=update $(basename "$0")

  # Renew system certificate unattended
  var_unattended=yes var_x509_action=renew $(basename "$0")

  # Export current Configuration
  $(basename "$0") --export-config
EOF
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================
#
# step specific CONFIGURATION VARIABLES
function init_app() {
  if [ -d "$CA_PATH" ]; then
    APP_TITLE="step-ca Admin"
    export STEPPATH="${CA_PATH}"
    grep -q "export STEPPATH=" /etc/profile || echo "export STEPPATH=${CA_PATH}" >> /etc/profile
    sed -i "/export STEPPATH=/c\export STEPPATH=${CA_PATH}" /etc/profile

    export STEPHOME="${CONFIG_PATH}"
    grep -q "export STEPHOME=" /etc/profile || echo "export STEPHOME=${CONFIG_PATH}" >> /etc/profile
    sed -i "/export STEPHOME=/c\export STEPHOME=${CONFIG_PATH}" /etc/profile

    CA_DEFAULTS="$CA_PATH/config/defaults.json"
    CA_CONFIG="$CA_PATH/config/ca.json"
    CA_CRT=$(jq -r .crt "$CA_CONFIG")
    CA_CRT_KEY=$(jq -r .key "$CA_CONFIG")
    CA_ROOT_KEY="$CA_PATH/secrets/root_ca_key"
    CA_TEMPLATE_CRT="$CA_PATH/templates/ca/intermediate_ca.tpl"
    CA_TEMPLATE_X509="$CA_PATH/templates/x509/leaf.tpl"
    CA_PROVISIONER_TYPE="JWK"
    CA_PROVISIONER=$(jq -r '.authority.provisioners.[] | select(.type=="JWK") | .name' "$CA_CONFIG")
    CA_PROVISIONER_PWD_FILE="$CA_PATH/encryption/provisioner.pwd"

    mkdir -p "$CONFIG_PATH/db-copy/"
    mkdir -p "$CERT_PATH/ca/_archive/"
  else
    APP_TITLE="step ACME Client"
    export STEPPATH="${CONFIG_PATH}"
    grep -q "export STEPPATH=" /etc/profile || echo "export STEPPATH=${CONFIG_PATH}" >> /etc/profile
    sed -i "/export STEPPATH=/c\export STEPPATH=${CONFIG_PATH}" /etc/profile

    export STEPHOME="${CONFIG_PATH}"
    grep -q "export STEPHOME=" /etc/profile || echo "export STEPHOME=${CONFIG_PATH}" >> /etc/profile
    sed -i "/export STEPHOME=/c\export STEPHOME=${CONFIG_PATH}" /etc/profile

    CA_DEFAULTS="$CONFIG_PATH/config/defaults.json"
    CA_PROVISIONER_TYPE="ACME"
    CA_PROVISIONER="acme@$(hostname -d)"
    CA_CRT="$CERT_PATH/intermediate_ca.crt"
  fi

  if [ -f "$CA_DEFAULTS" ]; then
    CA_URL=$(jq -r '."ca-url"' "$CA_DEFAULTS")
    [[ -n $CA_URL ]] && CA_FQDN=$(echo "$CA_URL" | awk -F 'https://' '{print $2}' | awk -F ':' '{print $1}') || CA_FQDN="step-ca.$(hostname -d)"
    CA_URL_ROOT="$CA_URL/roots.pem"
    CA_URL_CRT="$CA_URL/1.0/intermediates.pem"
    CA_URL_CRL="$CA_URL/1.0/crl"
    CA_FINGERPRINT=$(jq -r .fingerprint "$CA_DEFAULTS")
    CA_ROOT=$(jq -r .root "$CA_DEFAULTS")
    CA_ORG=$(step certificate inspect "${CA_ROOT}" --format=json | jq -r .subject.organization.[])
    CA_CN_ROOT=$(step certificate inspect "${CA_ROOT}" --format=json | jq -r .subject.common_name.[])
    CA_CN=$(step certificate inspect "${CA_URL_CRT}" --insecure --format=json | jq -r .subject.common_name.[])
    CA_CN_CRT=$(step certificate inspect "${CA_URL_CRT}" --insecure --format=json | jq -r .issuer.common_name.[])
    CA_VALIDITY_ROOT=$(step certificate inspect "${CA_ROOT}" --format=json | jq -r .validity.end)
    CA_VALIDITY_CRT=$(step certificate inspect "${CA_URL_CRT}" --insecure --bundle --format=json | jq -r .[1].validity.end)
    CA_SERIAL_ROOT=$(step certificate inspect "${CA_ROOT}" --format=json | jq -r .serial_number)
    CA_SERIAL_CRT=$(step certificate inspect "${CA_URL_CRT}" --insecure --bundle --format=json | jq -r .[1].serial_number)
  fi

  mkdir -p "$CERT_PATH/ssh/_archive/"
  mkdir -p "$CERT_PATH/x509/_archive/"
  mkdir -p "$KEY_PATH/_archive/"

  if [[ ! -d "$CA_PATH" ]] && [[ -f "$CA_DEFAULTS" ]]; then
    ca_download_intermediate
  fi
}

# GLOBAL CONFIGURATION VARIABLES
APP="step-cli"
APP_TYPE="addon"
APP_TITLE=""
APP_BACKTITLE="Proxmox VE Helper Scripts"
BINARY_PATH="/usr/bin/step"
CONFIG_PATH="/etc/step"
CERT_PATH="${CONFIG_PATH}/certs"
KEY_PATH="${CONFIG_PATH}/private"
SYS_CA_PATH="/usr/local/share/ca-certificates"
CA_PATH="/etc/step-ca"
CA_CONFIG=""
CA_DEFAULTS=""
CA_FINGERPRINT=""
CA_ORG=""
CA_CN=""
CA_CN_ROOT=""
CA_CN_CRT=""
CA_VALIDITY_ROOT=""
CA_VALIDITY_CRT=""
CA_SERIAL_ROOT=""
CA_SERIAL_CRT=""
CA_FQDN=""
CA_URL=""
CA_URL_ROOT=""
CA_URL_CRT=""
CA_URL_CRL=""
CA_ROOT="${CERT_PATH}/root_ca.crt"
CA_ROOT_KEY=""
CA_CRT=""
CA_CRT_KEY=""
CA_TEMPLATE_CRT=""
CA_TEMPLATE_X509=""
CA_PROVISIONER=""
CA_PROVISIONER_TYPE=""
CA_PROVISIONER_PWD_FILE=""

# Initialize all core functions (colors, formatting, icons, STD mode)
load_functions

# ==============================================================================
# OPTIONS
# Handle command line arguments
# ==============================================================================
case "${1:-}" in
  --help | -h)
    print_usage
    exit 0
    ;;
  --export-config)
    export_config_json
    exit 0
    ;;
esac

# ==============================================================================
# WHIPTAIL HELPER FUNCTIONS
# ==============================================================================
function whiptail_msgbox() {
  local TITLE=$1
  local TEXT=$2
  local LEN
  LEN=$(echo "$TEXT" | wc -l)
  local HIGHT=$(( LEN + 7 ))
  (( HIGHT > 30 )) && HIGHT=30
  local WIDTH=$(( ${#TITLE} + 16 ))
  local WIDTH_ARRAY=( "$WIDTH" $(( ${#TEXT} + 4 )) )
  for i in "${WIDTH_ARRAY[@]}"; do
    (( i > WIDTH )) && WIDTH=$i
  done
  (( WIDTH > 150 )) && WIDTH=150

  whiptail --backtitle "$APP_BACKTITLE" --title "$TITLE" --scrolltext --msgbox "$TEXT" "$HIGHT" "$WIDTH" 3>&1 1>&2 2>&3
}

function whiptail_inputbox() {
  local TITLE=$1
  local TEXT=$2
  local VALUE_INIT=$3
  local VALUE_INPUT
  local HIGHT=10
  local WIDTH=$(( ${#TITLE} + 16 ))
  local WIDTH_ARRAY=( "$WIDTH" $(( ${#TEXT} + 4 )) $(( ${#VALUE_INIT} + 8 )) )
  for i in "${WIDTH_ARRAY[@]}"; do
    (( i > WIDTH )) && WIDTH=$i
  done

  if VALUE_INPUT=$(whiptail --backtitle "$APP_BACKTITLE" --title "$TITLE" --inputbox "\n$TEXT" \
    "$HIGHT" "$WIDTH" "$VALUE_INIT" 3>&1 1>&2 2>&3); then
    echo "$VALUE_INPUT"
  else
    echo "$VALUE_INIT"
  fi
}

function whiptail_textbox() {
  local TITLE=$1
  local FILE=$2
  local LEN
  LEN=$(wc -l < "$FILE")
  local HIGHT=$(( LEN + 7 ))
  (( HIGHT > 30 )) && HIGHT=30
  local WIDTH=150

  whiptail --backtitle "$APP_BACKTITLE" --title "$TITLE" --scrolltext --textbox "$FILE" "$HIGHT" "$WIDTH" 3>&1 1>&2 2>&3
}

function whiptail_menu() {
  local TITLE=$1
  local TEXT="\nSelect an option:"
  local LEN=$(( ${#OPTIONS[@]} / 2 ))
  local HIGHT=$(( LEN + 9 ))
  local WIDTH=$(( ${#TITLE} + 16 ))
  local WIDTH_OFFSET=5
  local CHOICE
  local MAX_LEFT=0
  local MAX_RIGHT=0
  for ((i=0; i<${#OPTIONS[@]}; i+=2)); do
    (( ${#OPTIONS[i]} > MAX_LEFT )) && MAX_LEFT=${#OPTIONS[i]}
    (( ${#OPTIONS[$(( i+1 ))]} > MAX_RIGHT )) && MAX_RIGHT=${#OPTIONS[$(( i+1 ))]}
  done
  (( MAX_LEFT + MAX_RIGHT + WIDTH_OFFSET > WIDTH )) && WIDTH=$(( MAX_LEFT + MAX_RIGHT + WIDTH_OFFSET ))

  if CHOICE=$(whiptail --backtitle "$APP_BACKTITLE" --title "$TITLE" --menu "$TEXT" \
    "$HIGHT" "$WIDTH" "$LEN" "${OPTIONS[@]}" 3>&1 1>&2 2>&3 || true); then
    echo "$CHOICE"
  fi
}

function whiptail_checklist() {
  local TITLE=$1
  local TEXT=$2
  local -n LIST=$3
  local CHOICE
  local OPTIONS=()
  local WIDTH=$(( ${#TITLE} + 16 ))
  local WIDTH_OFFSET=15
  local MAX_LEFT=0
  local MAX_RIGHT=0

  for ((i=0; i<${#LIST[@]}; i+=2)); do
    local j=$(( i+1 ))
    (( ${#LIST[i]} > MAX_LEFT )) && MAX_LEFT=${#LIST[i]}
    (( ${#LIST[j]} > MAX_RIGHT )) && MAX_RIGHT=${#LIST[j]}
    OPTIONS+=("${LIST[i]}" "${LIST[j]}" "OFF")
  done
  (( MAX_LEFT + MAX_RIGHT + WIDTH_OFFSET > WIDTH )) && WIDTH=$(( MAX_LEFT + MAX_RIGHT + WIDTH_OFFSET ))
  local LEN=$(( ${#OPTIONS[@]} / 2 ))
  (( LEN > 21 )) && LEN=21
  local HIGHT=$(( LEN + 9 ))

  if CHOICE=$(whiptail --backtitle "$APP_BACKTITLE" --title "$TITLE" --scrolltext --checklist "$TEXT" \
    "$HIGHT" "$WIDTH" "$LEN" "${OPTIONS[@]}" 3>&1 1>&2 2>&3 | tr -d '"'); then
    echo "$CHOICE"
  fi
}

function whiptail_radiolist() {
  local TITLE=$1
  local TEXT=$2
  local -n LIST=$3
  local CHOICE
  local OPTIONS=()
  local WIDTH=$(( ${#TITLE} + 16 ))
  local WIDTH_OFFSET=15
  local MAX_LEFT=0
  local MAX_RIGHT=0

  for ((i=0; i<${#LIST[@]}; i+=2)); do
    local j=$(( i+1 ))
    (( ${#LIST[i]} > MAX_LEFT )) && MAX_LEFT=${#LIST[i]}
    (( ${#LIST[j]} > MAX_RIGHT )) && MAX_RIGHT=${#LIST[j]}
    OPTIONS+=("${LIST[i]}" "${LIST[j]}" "OFF")
  done
  (( MAX_LEFT + MAX_RIGHT + WIDTH_OFFSET > WIDTH )) && WIDTH=$(( MAX_LEFT + MAX_RIGHT + WIDTH_OFFSET ))
  local LEN=$(( ${#OPTIONS[@]} / 2 ))
  (( LEN > 21 )) && LEN=21
  local HIGHT=$(( LEN + 9 ))

  if CHOICE=$(whiptail --backtitle "$APP_BACKTITLE" --title "$TITLE" --scrolltext --radiolist "$TEXT" \
    "$HIGHT" "$WIDTH" "$LEN" "${OPTIONS[@]}" 3>&1 1>&2 2>&3 | tr -d '"'); then
    echo "$CHOICE"
  fi
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================
function resolve_ip() {
  local FQDN=$1
  local IP
  IP=$(dig +short "$FQDN")
 [[ -z "$IP" ]] && exit 1 || echo "$IP"
}

# ==============================================================================
# OS DETECTION
# ==============================================================================
function detect_os() {
  if grep -qi "alpine" /etc/os-release; then
    #OS="Alpine"
    PKG_UPDATE=""
    PKG_INSTALL="apk add --no-cache"
    PKG_UPGRADE="apk update"
    PKG_UNINSTALL="apk del"
    PKG_AUTOREMOVE=""
  elif grep -qi "arch" /etc/os-release; then
    #OS="Arch"
    PKG_UPDATE=""
    PKG_INSTALL="pacman -S"
    PKG_UPGRADE="pacman -Syu"
    PKG_UNINSTALL="pacman -Rs"
    PKG_AUTOREMOVE=""
  elif grep -qi "debian" /etc/os-release; then
    #OS="Debian"
    PKG_UPDATE="apt update"
    PKG_INSTALL="apt -y install"
    PKG_UPGRADE="apt -y upgrade"
    PKG_UNINSTALL="apt -y --purge remove"
    PKG_AUTOREMOVE="apt -y --purge autoremove"
    if ! [[ -f /etc/apt/sources.list.d/smallstep.sources ]]; then
      setup_deb822_repo \
        "smallstep" \
        "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
        "https://packages.smallstep.com/stable/debian" \
        "debs" \
        "main"
    fi
  elif grep -qi "ubuntu" /etc/os-release; then
    #OS="Ubuntu"
    PKG_UPDATE="apt update"
    PKG_INSTALL="apt -y install"
    PKG_UPGRADE="apt -y upgrade"
    PKG_UNINSTALL="apt -y --purge remove"
    PKG_AUTOREMOVE="apt -y --purge autoremove"
    if ! [[ -f /etc/apt/sources.list.d/smallstep.sources ]]; then
      setup_deb822_repo \
        "smallstep" \
        "https://packages.smallstep.com/keys/apt/repo-signing-key.gpg" \
        "https://packages.smallstep.com/stable/debian" \
        "debs" \
        "main"
    fi
  else
    die "Unsupported OS. Exiting."
  fi
}

# ==============================================================================
# INSTALL
# ==============================================================================
function install() {
  msg_info "Installing dependencies"
  detect_os
  # shellcheck disable=SC2086
  $STD $PKG_UPDATE
  # shellcheck disable=SC2086
  $STD $PKG_INSTALL curl whiptail dnsutils jq
  msg_ok "Installed dependencies"

  msg_info "Installing $APP"
  # shellcheck disable=SC2086
  $STD $PKG_INSTALL $APP
  rm -f "${BINARY_PATH}"
  cp -f /usr/bin/step-cli "${BINARY_PATH}"
  mkdir -p "$CONFIG_PATH"/certs
  mkdir -p "$CONFIG_PATH"/private

  cat <<'EOF' >/etc/systemd/system/cert-renewer@.service
[Unit]
Description=Certificate renewer for %i
After=network-online.target
Documentation=https://smallstep.com/docs/step-ca/certificate-authority-server-production
StartLimitIntervalSec=0
; PartOf=cert-renewer.target

[Service]
Type=oneshot
User=root

Environment=STEPPATH="/etc/step" CERT_LOCATION="/etc/step/certs/x509/%i.crt" KEY_LOCATION="/etc/step/private/%i.key"

; ExecCondition checks if the certificate is ready for renewal,
; based on the exit status of the command.
; (In systemd <242, you can use ExecStartPre= here.)
ExecCondition=/usr/bin/step certificate needs-renewal "${CERT_LOCATION}"

; ExecStart renews the certificate, if ExecStartPre was successful.
ExecStart=/usr/bin/step ca renew --force "${CERT_LOCATION}" "${KEY_LOCATION}"

; Try to reload or restart the systemd service that relies on this cert-renewer
; If the relying service doesn't exist, forge ahead.
; (In systemd <229, use 'reload-or-try-restart' instead of 'try-reload-or-restart')
ExecStartPost=/usr/bin/env sh -c "! systemctl --quiet is-active %i.service || systemctl try-reload-or-restart %i"

[Install]
WantedBy=multi-user.target
EOF

  cat <<'EOF' >/etc/systemd/system/cert-renewer@.timer
[Unit]
Description=Timer for certificate renewal of %i
Documentation=https://smallstep.com/docs/step-ca/certificate-authority-server-production
; PartOf=cert-renewer.target

[Timer]
Persistent=true

; Run the timer unit every 2 minutes.
OnCalendar=*:1/2

; Always run the timer on time.
AccuracySec=1us

; Add jitter to prevent a "thundering hurd" of simultaneous certificate renewals.
RandomizedDelaySec=12s

[Install]
WantedBy=timers.target
EOF
  $STD systemctl daemon-reload
  msg_ok "Installed $APP"

  bootstrap "" || die "Installation of step-ca Root Certificate failed!"
  x509_request "" || die "Main - Request System Certificate failed!"
}

# ==============================================================================
# UPDATE
# ==============================================================================
function update() {
  [[ ! -e $BINARY_PATH ]] && die "$APP is not installed!"
  msg_info "Updating $APP"
  detect_os
  # shellcheck disable=SC2086
  $STD $PKG_UPDATE
  # shellcheck disable=SC2086
  $STD $PKG_UPGRADE $APP
  rm -f "${BINARY_PATH}"
  cp -f /usr/bin/step-cli "${BINARY_PATH}"
  msg_ok "Updated $APP successfully"
}

# ==============================================================================
# UNINSTALL
# ==============================================================================
function uninstall() {
  msg_info "Uninstalling $APP"
  if [ -f "${CA_CONFIG}" ]; then
    die "Uninstalling $APP on a CA server is not supported!"
  else
    detect_os
    rm -f "${SYS_CA_PATH}"/"${CA_ORG}"*.crt
    $STD update-ca-certificates || die "Update of System CA Certificates failed!"
    [ -f /etc/systemd/system/cert-renewer@.timer ] && $STD systemctl -f disable cert-renewer@.timer
    [ -f /etc/systemd/system/cert-renewer@.service ] && $STD systemctl -f disable cert-renewer@.service
    $STD systemctl -f stop cert-renewer@*.timer
    $STD systemctl -f stop cert-renewer@*.service
    # shellcheck disable=SC2086
    $STD $PKG_UNINSTALL $APP
    # shellcheck disable=SC2086
    $STD $PKG_AUTOREMOVE
    rm -f "${BINARY_PATH}"
    rm -rf "${CONFIG_PATH}"
    rm -f "/etc/apt/sources.list.d/smallstep.sources"
    rm -f "/usr/local/bin/update_${APP,,}"
    rm -f "/etc/systemd/system/cert-renewer@.service"
    rm -f "/etc/systemd/system/cert-renewer@.timer"
    systemctl daemon-reload
    msg_ok "Uninstalled $APP"
  fi
}

# ==============================================================================
# CORE FUNCTIONS
# ==============================================================================
function bootstrap() {
  local BACK_TO_MENU="${1:-}"
  [[ $var_unattended == "yes" ]] && [[ -f $CA_DEFAULTS ]] || bootstrap_menu
  msg_info "Installing Root Certificate by Certificate Authority '$CA_FQDN'"
  $STD echo
  $STD step ca bootstrap -f --ca-url "$CA_URL" --install --fingerprint "$CA_FINGERPRINT" || die "step-ca Bootstrapping failed!"
  init_app
  $STD step certificate install --all "$CA_ROOT" || die "Installation of step-ca Root Certificate failed!"
  $STD update-ca-certificates || die "Update of System CA Certificates failed!"
  $STD step certificate inspect "$CA_URL" || die "Inspection of step-ca Root Certificate failed!"
  msg_ok "Installed Root Certificate by Certificate Authority '$CA_FQDN'"
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function x509_request() {
  local BACK_TO_MENU="${1:-}"
  FQDN="$(hostname -f)"
  HOST="$(hostname)"
  IP=$(resolve_ip "${FQDN}") || die "Resolution failed for ${FQDN}!"
  SAN=""
  VALID_TO="168h" # Default validity of 7 days (168 hours)

  [[ $var_unattended == "yes" ]] && [[ -f $CA_DEFAULTS ]] || x509_request_menu
  msg_info "Requesting x509 Certificate for CN '$FQDN' by '$CA_PROVISIONER'"
  local FLAGS=(--force
    --not-after="$VALID_TO"
    --provisioner="$CA_PROVISIONER"
    --set country="DE"
    --set organization="$CA_ORG"
    --set organizationalUnit="MyHomeLab"
    --set issuingCertificateURL="$CA_URL_CRT"
    --set crlDistributionPoints="$CA_URL_CRL")
  [ "$CA_PROVISIONER_TYPE" = "JWK" ] && [ -f "$CA_PROVISIONER_PWD_FILE" ] && FLAGS+=(--provisioner-password-file="$CA_PROVISIONER_PWD_FILE")
  local SAN_ITEMS=("$FQDN" "$HOST" "$IP" "$SAN")
  for item in "${SAN_ITEMS[@]}"; do
    [ ! -z "$item" ] && FLAGS+=(--san "$item")
  done

  $STD echo
  $STD step ca certificate "$FQDN" \
    "${CERT_PATH}"/x509/"$FQDN".crt \
    "${KEY_PATH}"/"$FQDN".key \
    "${FLAGS[@]}" || die "Certificate Signing Request (CSR) by $CA_PROVISIONER failed!"
  msg_ok "Requested x509 Certificate for CN '$FQDN' by '$CA_PROVISIONER'"

  if [ "$CA_PROVISIONER_TYPE" = "ACME" ]; then
    msg_info "Installing Daemon for Renewal of x509 Certificate for CN '$FQDN'"
    $STD systemctl enable --now cert-renewer@"${FQDN}".timer
    $STD systemctl list-units cert-renewer@\*.timer
    msg_ok "Installed Daemon for Renewal of x509 Certificate for CN '$FQDN'"
  fi
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function x509_renew() {
  local BACK_TO_MENU="${1:-}"
  x509_certs_menu "Renew"
  for SERIAL in "${CERT_ARRAY[@]}"; do
    x509_query
    msg_info "Renew x509 Certificate for CN '${CN}' with Serial Number '${SERIAL}'"
    if [ -f "${CRT}" ] && [ -f "${KEY}" ]; then
      CRT_OLD="${CERT_PATH}/x509/_archive/${CN}_$(date +%Y%m%d%H%M%S).crt"
      KEY_OLD="${KEY_PATH}/_archive/${CN}_$(date +%Y%m%d%H%M%S).key"
      cp "${CRT}" "${CRT_OLD}" || die "Failed to backup ${CRT}!"
      cp "${KEY}" "${KEY_OLD}" || die "Failed to backup ${KEY}!"
      $STD echo
      $STD step ca renew --force "${CRT}" "${KEY}" || die "Failed to renew certificate!"
      $STD step ca revoke --cert "${CRT_OLD}" --key "${KEY_OLD}"
    else
      die "Failed to renew certificate!"
    fi
    msg_ok "Renewed x509 Certificate for CN '${CN}'"
  done
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function x509_revoke() {
  local BACK_TO_MENU="${1:-}"
  x509_certs_menu "Revoke"
  for SERIAL in "${CERT_ARRAY[@]}"; do
    x509_query
    msg_info "Revoke x509 Certificate for CN '${CN}' with Serial Number '${SERIAL}'"
    if [ -f "${CRT}" ] && [ -f "${KEY}" ]; then
      $STD echo
      $STD step ca revoke --cert "${CRT}" --key "${KEY}"
      rm -f "${CRT}" || die "Failed to delete ${CRT}!"
      rm -f "${KEY}" || die "Failed to delete ${KEY}!"
    elif [[ "$CA_PROVISIONER_TYPE" == "JWK" ]] && [ -f "$CA_PROVISIONER_PWD_FILE" ]; then
      $STD echo
      TOKEN=$(step ca token --provisioner="$CA_PROVISIONER" --provisioner-password-file="$CA_PROVISIONER_PWD_FILE" --revoke "${SERIAL}")
      $STD echo
      $STD step ca revoke --token "$TOKEN" "${SERIAL}" || die "Failed to revoke certificate!"
    else
      die "Failed to revoke certificate!"
    fi
    msg_ok "Revoked x509 Certificate for CN '${CN}' with Serial Number '${SERIAL}'"
  done
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function x509_list() {
  local BACK_TO_MENU="${1:-}"
  x509_view
  whiptail_textbox "Certificates Issued by $CA_FQDN" "$CERT_PATH/x509/x509Certs.txt"
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function ca_renew_intermediate() {
  local BACK_TO_MENU="${1:-}"
  FQDN="$(hostname -f)"
  HOST="$(hostname)"
  IP=$(resolve_ip "${FQDN}") || die "Resolution failed for ${FQDN}!"
  SAN=""
  VALID_TO="87600h" # Default validity of 10 years (87600 hours)

  [[ $var_unattended == "yes" ]] && [[ -f $CA_DEFAULTS ]] || x509_request_menu
  msg_info "Renewing CA Intermediate Certificate ($CA_CRT)"
  local FLAGS=(--force
    --template="$CA_TEMPLATE_CRT"
    --ca="$CA_ROOT"
    --ca-key="$CA_ROOT_KEY"
    --not-after="$VALID_TO"
    --ca-password-file="/etc/step-ca/encryption/ca.pwd"
    --password-file="/etc/step-ca/encryption/ca.pwd"
    --bundle
    --set country="DE"
    --set organization="$CA_ORG"
    --set organizationalUnit="MyHomeLab"
    --set issuingCertificateURL="$CA_URL_ROOT"
    --set crlDistributionPoints="$CA_URL_CRL")

  $STD echo
  $STD step certificate create "${CA_CN_CRT//\"/}" \
    "${CA_CRT}" \
    "${CA_CRT_KEY}" \
    "${FLAGS[@]}" || die "Certificate Signing Request (CSR) by $CA_PROVISIONER failed!"

  chown -R step /etc/step-ca
  chgrp -R step /etc/step-ca
  msg_ok "Renewed CA Intermediate Certificate ($CA_CRT)"
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function x509_inspect_uri() {
  local CERT_URI="$1"
  local ISSUING_CA="$2"
  local CRL_ENDPOINT="$3"
  local ROOTS="$4"
  local CERT_VALIDITY=""
  local CERT_VALIDATION=""

  local FLAGS=(--verbose --verify-crl)
  [ "$ISSUING_CA" ] && FLAGS+=(--issuing-ca="$ISSUING_CA")
  [ "$CRL_ENDPOINT" ] && FLAGS+=(--crl-endpoint="$CRL_ENDPOINT")
  CERT_VALIDITY=$(step certificate verify "${FLAGS[@]}" "$CERT_URI" 2>&1 || true)

  while read -r LINE; do
    CERT_VALIDATION+="${TAB}${TAB}- $LINE\n"
  done <<< "$CERT_VALIDITY"
  local CERT_INSPECT="Certificate Path Validation:\n"
  CERT_INSPECT+="${TAB}Location: $CERT_URI\n"
  CERT_INSPECT+="$CERT_VALIDATION\n"

  local FLAGS=(--bundle)
  [ "$ROOTS" ] && FLAGS+=(--roots="$ROOTS")
  CERT_INSPECT+=$(step certificate inspect "${FLAGS[@]}" "$CERT_URI" 2>&1 || true)

  whiptail_msgbox "Certificate Path Validation: $(echo "${CERT_VALIDITY}" | tail -n1)" "$CERT_INSPECT"
}

function x509_inspect() {
  local BACK_TO_MENU="${1:-}"
  x509_certs_menu "Inspect"
  for SERIAL in "${CERT_ARRAY[@]}"; do
    x509_query
    if [ -f "$CRT" ]; then
      # shellcheck disable=SC2143
      if [[ $(step certificate inspect "${CRT}" | grep "${SERIAL}") ]]; then
        #x509_inspect_uri CERT_URI ISSUING_CA CRL_ENDPOINT ROOTS"
        x509_inspect_uri "$CRT" "$CA_CRT" "$CA_URL_CRL" ""
      else
        die "x509 Certificate Serial Number ${SERIAL} mismatch for CN '${CN}'!"
      fi
    else
      whiptail_msgbox "Certificates Issued by $CA_FQDN" "x509 Certificate for CN '${CN}' not found on localhost."
    fi
  done
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function ca_download_intermediate() {
  step certificate inspect --bundle --format pem "${CA_URL}" > "$CERT_PATH/intermediate_ca.crt"
  awk -v path="$CERT_PATH" '/BEGIN CERTIFICATE/{n++} {print >(path "/cert-" n ".pem")}' "$CERT_PATH/intermediate_ca.crt"
  [ -f "$CERT_PATH/cert-1.pem" ] && rm "$CERT_PATH/cert-1.pem"
  [ -f "$CERT_PATH/cert-2.pem" ] && mv "$CERT_PATH/cert-2.pem" "$CERT_PATH/intermediate_ca.crt"
  [ -f "$CERT_PATH/cert-3.pem" ] && cat "$CERT_PATH/cert-3.pem" >> "$CERT_PATH/intermediate_ca.crt"; rm "$CERT_PATH/cert-3.pem"
  local SYS_CA_CRT="${SYS_CA_PATH}/${CA_CN_CRT// /_}_${CA_SERIAL_CRT}.crt"
  cp -f "$CA_CRT" "$SYS_CA_CRT" || die "Installation of step-ca Intermediate Certificate failed!"
  $STD update-ca-certificates || die "Update of System CA Certificates failed!"
}

function ca_inspect_root() {
  local BACK_TO_MENU="${1:-}"
  if [ -f "${CA_ROOT}" ]; then
    #x509_inspect_uri CERT_URI ISSUING_CA CRL_ENDPOINT ROOTS"
    x509_inspect_uri "$CA_ROOT" "$CA_CRT" "$CA_URL_CRL" "$CA_ROOT"
  else
    whiptail_msgbox "Certificates Issued by $CA_FQDN" "Root CA Certificate not found on localhost."
  fi
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function ca_inspect_root_url() {
  local BACK_TO_MENU="${1:-}"
  #x509_inspect_uri CERT_URI ISSUING_CA CRL_ENDPOINT ROOTS"
  x509_inspect_uri "$CA_URL_ROOT" "$CA_CRT" "$CA_URL_CRL" "$CA_ROOT"
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function ca_inspect_intermediate() {
  local BACK_TO_MENU="${1:-}"
  if [ -f "${CA_CRT}" ]; then
    #x509_inspect_uri CERT_URI ISSUING_CA CRL_ENDPOINT ROOTS"
    x509_inspect_uri "$CA_CRT" "$CA_CRT" "$CA_URL_CRL" "$CA_ROOT"
  else
    whiptail_msgbox "Certificates Issued by $CA_FQDN" "Intermediate CA Certificate not found on localhost."
  fi
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function ca_inspect_intermediate_url() {
  local BACK_TO_MENU="${1:-}"
  #x509_inspect_uri CERT_URI ISSUING_CA CRL_ENDPOINT ROOTS"
  x509_inspect_uri "$CA_URL_CRT" "$CA_CRT" "$CA_URL_CRL" "$CA_ROOT"
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function ca_inspect_service_url() {
  local BACK_TO_MENU="${1:-}"
  #x509_inspect_uri CERT_URI ISSUING_CA CRL_ENDPOINT ROOTS"
  x509_inspect_uri "$CA_URL" "$CA_CRT" "$CA_URL_CRL" "$CA_ROOT"
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function x509_inspect_crl() {
  local BACK_TO_MENU="${1:-}"
  local CA_CRL=""
  if [ -f "${CA_ROOT}" ]; then
    CA_CRL=$(step crl inspect --ca="$CA_CRT" "$CA_URL_CRL")
    whiptail_msgbox "Certificate Revocation List by $CA_FQDN" "$CA_CRL"
  else
    whiptail_msgbox "Certificates Issued by $CA_FQDN" "Root CA Certificate not found on localhost."
  fi
  [[ "$BACK_TO_MENU" ]] && "$BACK_TO_MENU" || true
}

function x509_query() {
  CRT=""
  KEY=""
  #SERIAL CN TYPE FILE VALIDITY NotBefore NotAfter
  CN="$(cat "$CERT_PATH/x509/x509Certs.txt" | grep "${SERIAL}" | awk '{print $2}' )"
  TYPE="$(cat "$CERT_PATH/x509/x509Certs.txt" | grep "${SERIAL}" | awk '{print $3}')"
  FILE="$(cat "$CERT_PATH/x509/x509Certs.txt" | grep "${SERIAL}" | awk '{print $4}')"
  if [[ "$FILE" == "local" ]]; then
    CRT="$CERT_PATH/x509/$CN.crt"
    KEY="$KEY_PATH/$CN.key"
  fi
}

function x509_view(){
  CERT_LIST=()
  local CERT_FILE_ARRAY=("$CERT_PATH/x509/"*.crt)
  local FILE="none"

  echo "Serial Number|CN|Type|File|Validity|Not Before|Not After" > "$CERT_PATH/x509/x509Certs.txt"
  if [ -d "$CA_PATH/db" ]; then
    cp --recursive --force "$CA_PATH/db/"* "$CONFIG_PATH/db-copy/"
    cp --recursive --force "$CA_PATH/certs/"* "$CONFIG_PATH/certs/ca/"
    if [[ $(step-badger x509Certs "$CONFIG_PATH/db-copy" 2>/dev/null) ]]; then
      local DB_EXPORT=""
      local FLAGS=("--provisioner")
      DB_EXPORT=$(step-badger x509Certs "$CONFIG_PATH/db-copy" "${FLAGS[@]}" 2>/dev/null | sed '1d')
      # shellcheck disable=SC2034
      while read -r SERIAL SUBJECT TYPE REQUESTER NotBefore NotAfter VALIDITY; do
        FILE="none"
        CN=$(echo "$SUBJECT" | awk -F 'CN=' '{print $2}' | awk -F ',' '{print $1}')
        local CRT="$CERT_PATH/x509/$CN.crt"
        if [ -f "${CRT}" ] && step certificate inspect "${CRT}" | grep -q "${SERIAL}"; then
          FILE="local"
        fi
        echo "$SERIAL|$CN|$TYPE|$FILE|$VALIDITY|$NotBefore|$NotAfter" >> "$CERT_PATH/x509/x509Certs.txt"
        CERT_LIST+=("$SERIAL" "$CN|$TYPE|$FILE|$VALIDITY|$NotAfter")
      done <<< "$DB_EXPORT"
    fi
  else
    for ITEM in "${CERT_FILE_ARRAY[@]}"; do
      FILE="none"
      [ -f "${ITEM}" ] || break
      SERIAL=$(step certificate inspect "${ITEM}" --format=json | jq -r .serial_number)
      CN=$(step certificate inspect "${ITEM}" --format=json | jq -r .subject.common_name.[])
      TYPE=$(step certificate inspect "${ITEM}" --format=json | jq -r .extensions.step_provisioner.type)
      FILE="local"
      NotBefore=$(step certificate inspect "${ITEM}" --format=json | jq -r .validity.start)
      NotAfter=$(step certificate inspect "${ITEM}" --format=json | jq -r .validity.end)
      [ "$(date -d "${NotAfter}" +%s)" -gt "$(date +%s)" ] && [ "$(date -d "${NotBefore}" +%s)" -lt "$(date +%s)" ] && VALIDITY="Valid" || VALIDITY="Expired"
      echo "$SERIAL|$CN|$TYPE|$FILE|$VALIDITY|$NotBefore|$NotAfter" >> "$CERT_PATH/x509/x509Certs.txt"
      CERT_LIST+=("$SERIAL" "$CN|$TYPE|$FILE|$VALIDITY|$NotAfter")
    done
  fi
  # shellcheck disable=SC2094
  cat "$CERT_PATH/x509/x509Certs.txt" | column -t -s '|' > "$CERT_PATH/x509/x509Certs.txt"
  TOTAL_CERTS=$(( $(wc -l < "$CERT_PATH/x509/x509Certs.txt") - 1 ))
  VALID_CERTS=$(( $(grep -c "Valid" "$CERT_PATH/x509/x509Certs.txt") - 1))
  EXPIRED_CERTS=$(( TOTAL_CERTS - VALID_CERTS ))
  echo -e "\n\nTotal Certificates  : ${TOTAL_CERTS}\nValid Certificates  : ${VALID_CERTS}\nExpired Certificates: ${EXPIRED_CERTS}" >> "$CERT_PATH/x509/x509Certs.txt"
}

#function ssh_badger_list() {
#  CERT_LIST=""
#  cp --recursive --force "$CA_PATH/db/"* "$CONFIG_PATH/db-copy/"
#  cp --recursive --force "$CA_PATH/certs/"* "$CONFIG_PATH/certs/ca/"
#  if [[ $(step-badger sshCerts "${CONFIG_PATH}/db-copy" 2>/dev/null) ]]; then
#    CERT_LIST=$(step-badgersshCerts ${CONFIG_PATH}/db-copy 2>/dev/null)
#  fi
#}

# ==============================================================================
# MENU FUNCTIONS
# Interactive prompts via Whiptail dialogs
# ==============================================================================
function main_menu() {
  local CHOICE
  OPTIONS=(Install "Install $APP"
    Update "Update $APP"
    Uninstall "Uninstall $APP"
    Maintain "Maintain Certificates"
    Config "Export current Configuration as JSON")

  CHOICE=$(whiptail_menu "$APP_TITLE")
  case "$CHOICE" in
    Install) install ;;
    Update) update ;;
    Uninstall) uninstall ;;
    Maintain) maintain_menu ;;
    Config) export_config_json ;;
    *) exit 0 ;;
  esac
}

function maintain_menu() {
  [[ ! -e $BINARY_PATH ]] && die "$APP is not installed!"

  local CHOICE
  OPTIONS=(x509 "Maintain x509 Certificate"
    ssh "Maintain ssh Certificate"
    ca "Maintain Certificate Authority")

  CHOICE=$(whiptail_menu "$APP_TITLE")
  case "$CHOICE" in
    x509) x509_maintain_menu ;;
    ssh) ssh_maintain_menu ;;
    ca) ca_maintain_menu ;;
    *) exit 0 ;;
  esac
}

function x509_maintain_menu() {
  local CHOICE
  OPTIONS=()
  [ -d "$CA_PATH/config" ] || OPTIONS+=(Bootstrap "Install step-ca Root Certificate")
  OPTIONS+=(Request "Certificate Signing Request (CSR) by $CA_PROVISIONER_TYPE"
    Renew "Renew Certificate by $CA_PROVISIONER_TYPE"
    Revoke "Revoke Certificate by $CA_PROVISIONER_TYPE"
    Inspect "Inspect Certificate by $CA_PROVISIONER_TYPE"
    List "List Certificates"
    CRL "Certificate Revocation List")

  CHOICE=$(whiptail_menu "$APP_TITLE")
  case "$CHOICE" in
    Bootstrap) bootstrap "x509_maintain_menu" ;;
    Request) x509_request "x509_maintain_menu" ;;
    Renew) x509_renew "x509_maintain_menu" ;;
    Revoke) x509_revoke "x509_maintain_menu" ;;
    Inspect) x509_inspect "x509_maintain_menu" ;;
    List) x509_list "x509_maintain_menu" ;;
    CRL) x509_inspect_crl "x509_maintain_menu" ;;
    *) exit 0 ;;
  esac
}

function bootstrap_menu() {
  local CHOICE
  bootstrap_fqdn_check
  bootstrap_fingerprint_check

  OPTIONS=("step-ca FQDN" "$CA_FQDN"
    "step-ca Fingerprint" "$CA_FINGERPRINT"
    " " " "
    "<Continue>" "Install step-ca Root Certificate")
  local TITLE="step-ca Bootstrap Options"

  CHOICE=$(whiptail_menu "$TITLE")
  case "$CHOICE" in
    "step-ca FQDN")
      CA_FQDN=$(whiptail_inputbox "$TITLE" "step-ca FQDN (e.g. $CA_FQDN)" "$CA_FQDN")
      CA_URL="https://$CA_FQDN"
      bootstrap_menu
      ;;
    "step-ca Fingerprint")
      CA_FINGERPRINT=$(whiptail_inputbox "$TITLE" "step-ca Fingerprint" "$CA_FINGERPRINT")
      bootstrap_menu
      ;;
    " ")
      bootstrap_menu
      ;;
    "<Continue>")
      bootstrap_fqdn_check || bootstrap_menu
      ;;
    *) x509_maintain_menu ;;
  esac
}

function bootstrap_fqdn_check() {
  if [[ -z $CA_FQDN ]]; then
    CA_FQDN="Please change!"
  else
    CA_IP=$(resolve_ip "${CA_FQDN}")
    if [[ -z $CA_IP ]]; then
      CA_FQDN="DNS Resolution failed - Please change!"
    fi
  fi
}

function bootstrap_fingerprint_check() {
  if [[ -z $CA_FINGERPRINT ]]; then
    CA_FINGERPRINT="Please change!"
  fi
}

function x509_request_menu() {
  local CHOICE
  OPTIONS=("FQDN" "$FQDN"
    "Hostname" "$HOST"
    "IP Address" "$IP"
    "Subject Alternative Name(s) (SANs)" "$SAN"
    "Validity" "$VALID_TO"
    "Provisioner" "$CA_PROVISIONER"
    " " " "
    "<Continue>" "Request Certificate by $CA_PROVISIONER")
  local TITLE="Certificate Signing Request (CSR) by $CA_PROVISIONER_TYPE"

  CHOICE=$(whiptail_menu "$TITLE")
  case "$CHOICE" in
    "FQDN")
      FQDN=$(whiptail_inputbox "$TITLE" "FQDN (e.g. mylxc.example.com)" "$FQDN")
      HOST=$(echo "$FQDN" | awk -F'.' '{print $1}')
      IP=$(resolve_ip "${FQDN}") || die "Resolution failed for ${FQDN}!"
      x509_request_menu
      ;;
    "Hostname")
      HOST=$(whiptail_inputbox "$TITLE" "Hostname (e.g. mylxc)" "$HOST")
      x509_request_menu
      ;;
    "IP Address")
      IP=$(whiptail_inputbox "$TITLE" "IP Address (e.g. x.x.x.x)" "$IP")
      x509_request_menu
      ;;
    "Subject Alternative Name(s) (SANs)")
      SAN=$(whiptail_inputbox "$TITLE" "Subject Alternative Name(s) (SAN) (e.g. e.g. myapp-1.example.com, myapp-2.example.com)" "$SAN")
      x509_request_menu
      ;;
    "Validity")
      VALID_TO=$(whiptail_inputbox "$TITLE" "Validity (e.g. 168h, 30m0s or 2034-12-31T23:59:59Z)" "$VALID_TO")
      x509_request_menu
      ;;
    "Provisioner")
      CA_PROVISIONER=$(whiptail_inputbox "$TITLE" "Provisioner (e.g. $CA_PROVISIONER)" "$CA_PROVISIONER")
      x509_request_menu
      ;;
    " ")
      x509_request_menu
      ;;
    "<Continue>") ;;
    *) x509_maintain_menu ;;
  esac
}

function x509_certs_menu() {
  local CERT_ACTION="$1"
  local CHOICE=""
  x509_view
  if [[ ${#CERT_LIST[@]} -gt 0 ]]; then
    CHOICE=$(whiptail_checklist "Certificates Issued by $CA_FQDN" "\nSelect Certificate(s) to ${CERT_ACTION}:" "CERT_LIST")
  else
    whiptail_msgbox "Certificates Issued by $CA_FQDN" "No certificate(s) found on localhost."
  fi
  # shellcheck disable=SC2206
  CERT_ARRAY=(${CHOICE})
  if [ ${#CERT_ARRAY[@]} -eq 0 ]; then
    if [ -z "$var_x509_action" ]; then
      x509_maintain_menu
    else
      msg_warn "No certificate(s) selected or found on localhost."
      exit 1
    fi
  fi
}

function ssh_maintain_menu() {
  die "Maintain ssh Certificate - To be implemented in future"
}

function ca_maintain_menu() {
  local CHOICE
  OPTIONS=("renew" "Renew CA Intermediate Certificate ($CA_CRT)"
    "inspect-root" "Inspect CA Root Certificate ($CA_ROOT)"
    "inspect-root-url" "Inspect CA Root Certificate ($CA_URL_ROOT)"
    "inspect-intermediate" "Inspect CA Intermediate Certificate ($CA_CRT)"
    "inspect-intermediate-url" "Inspect CA Intermediate Certificate ($CA_URL_CRT)"
    "inspect-service-url" "Inspect CA Service Certificate ($CA_URL)")

  CHOICE=$(whiptail_menu "$APP_TITLE")
  case "$CHOICE" in
    "renew") ca_renew_intermediate "ca_maintain_menu" ;;
    "inspect-root") ca_inspect_root "ca_maintain_menu" ;;
    "inspect-root-url") ca_inspect_root_url "ca_maintain_menu" ;;
    "inspect-intermediate") ca_inspect_intermediate "ca_maintain_menu" ;;
    "inspect-intermediate-url") ca_inspect_intermediate_url "ca_maintain_menu" ;;
    "inspect-service-url") ca_inspect_service_url "ca_maintain_menu" ;;
    *) exit 0 ;;
  esac
}

# ==============================================================================
# MAIN
# ==============================================================================
init_app
header_info "step-admin"

case "$var_x509_action" in
  bootstrap)
    bootstrap
    exit 0
    ;;
  request)
    x509_request
    exit 0
    ;;
  renew)
    x509_renew
    exit 0
    ;;
  revoke)
    x509_revoke
    exit 0
    ;;
  inspect)
    x509_inspect
    exit 0
    ;;
  list)
    x509_list
    exit 0
    ;;
  crl)
    x509_inspect_crl
    exit 0
    ;;
esac

case "$var_cert_type" in
  x509) x509_maintain_menu ;;
  ssh) ssh_maintain_menu ;;
  ca) ca_maintain_menu ;;
esac

#
# *) NO use of CONFIGURATION VARIABLES for interactive prompts via Whiptail dialogs
#
case "$var_action" in
  install) install ;;
  update) update ;;
  uninstall) uninstall ;;
  maintain) maintain_menu ;;
  export-config) export_config_json ;;
  *) main_menu ;;
esac
