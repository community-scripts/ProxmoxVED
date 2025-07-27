#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Arian Nasr (arian-nasr)
# Updated by: Javier Pastor (vsc55)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.freepbx.org/

INSTALL_URL="https://github.com/FreePBX/sng_freepbx_debian_install/raw/master/sng_freepbx_debian_install.sh"
INSTALL_PATH="/opt/sng_freepbx_debian_install.sh"

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Downloading FreePBX installation script..."
if curl -fsSL "$INSTALL_URL" -o "$INSTALL_PATH"; then
  msg_ok "Download completed successfully"
else
  curl_exit_code=$?
  msg_error "Error downloading FreePBX installation script (curl exit code: $curl_exit_code)"
  msg_error "Aborting!"
  exit 1
fi

ONLY_OPENSOURCE="${ONLY_OPENSOURCE:-no}"
REMOVE_FIREWALL="${REMOVE_FIREWALL:-no}"
msg_ok "Remove Commercial modules is set to: $ONLY_OPENSOURCE"
msg_ok "Remove Firewall module is set to: $REMOVE_FIREWALL"

if [[ "$VERBOSE" == "yes" ]]; then
  msg_info "Installing FreePBX (Verbose)\n"
else
  msg_info "Installing FreePBX, be patient, this takes time..."
fi
$STD bash "$INSTALL_PATH"

if [[ $ONLY_OPENSOURCE == "yes" ]]; then
  msg_info "Removing Commercial modules..."

  max=5
  count=0
  while fwconsole ma list | awk '/Commercial/ {found=1} END {exit !found}'; do
    count=$((count + 1))
    while read -r module; do
      msg_info "Removing module: $module"

      if [[ "$REMOVE_FIREWALL" == "no" ]] && [[ "$module" == "sysadmin" ]]; then
        msg_warn "Skipping sysadmin module removal, it is required for Firewall!"
        continue
      fi

      code=0
      $STD fwconsole ma -f remove $module || code=$?
      if [[ $code -ne 0 ]]; then
        msg_error "Module $module could not be removed - error code $code"
      else
        msg_ok "Module $module removed successfully"
      fi
    done < <(fwconsole ma list | awk '/Commercial/ {print $2}')

    fwconsole ma list | awk '/Commercial/ {found=1} END {exit !found}' || break

    if [[ $count -ge $max ]]; then
      break
    else
      msg_warn "Not all commercial modules could be removed, retrying (attempt $count of $max)..."
    fi
  done

  if fwconsole ma list | awk '/Commercial/ {found=1} END {exit !found}'; then
    msg_warn "Some commercial modules could not be removed, please check the web interface for removal manually!"
  else
    msg_ok "Removed all commercial modules successfully"
  fi

  msg_info "Reloading FreePBX..."
  $STD fwconsole reload
  msg_ok "FreePBX reloaded completely"
fi
msg_ok "Installed FreePBX finished"

motd_ssh
customize

msg_info "Cleaning up"
rm -f "$INSTALL_PATH"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
