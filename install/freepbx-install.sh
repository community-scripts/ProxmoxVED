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

ONLY_OPENSOURCE="${ONLY_OPENSOURCE:-no}"
REMOVE_FIREWALL="${REMOVE_FIREWALL:-no}"
msg_ok "Remove Commercial modules is set to: $ONLY_OPENSOURCE"
msg_ok "Remove Firewall module is set to: $REMOVE_FIREWALL"

msg_info "Downloading FreePBX installation script..."
if curl -fsSL "$INSTALL_URL" -o "$INSTALL_PATH"; then
  msg_ok "Download completed successfully"
else
  curl_exit_code=$?
  msg_error "Error downloading FreePBX installation script (curl exit code: $curl_exit_code)"
  msg_error "Aborting!"
  exit 1
fi

if [[ "$VERBOSE" == "yes" ]]; then
  msg_info "Installing FreePBX (Verbose)\n"
else
  msg_info "Installing FreePBX, be patient, this takes time..."
fi
$STD bash "$INSTALL_PATH"

if [[ $ONLY_OPENSOURCE == "yes" ]]; then
  msg_info "Removing Commercial modules..."

  end_count=0
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

    [[ $count -ge $max ]] && break

    com_list=$(fwconsole ma list)
    end_count=$(awk '/Commercial/ {count++} END {print count + 0}' <<< "$com_list")
    awk '/Commercial/ {found=1} END {exit !found}' <<< "$com_list" || break
    if [[ "$REMOVE_FIREWALL" == "no" ]] && \
       [[ $end_count -eq 1 ]] && \
       [[ $(awk '/Commercial/ {print $2}' <<< "$com_list") == "sysadmin" ]]; then
      break
    fi

    msg_warn "Not all commercial modules could be removed, retrying (attempt $count of $max)..."
  done

  if [[ $REMOVE_FIREWALL == "yes" ]] && [[ $end_count -gt 0 ]]; then
    msg_info "Removing Firewall module..."
    if $STD fwconsole ma -f remove firewall; then
      msg_ok "Firewall module removed successfully"
    else
      msg_error "Firewall module could not be removed, please check manually!"
    fi
  fi

  if [[ $end_count -eq 0 ]]; then
    msg_ok "All commercial modules removed successfully"
  elif [[ $end_count -eq 1 ]] && [[ $REMOVE_FIREWALL == "no" ]]  && [[ $(fwconsole ma list | awk '/Commercial/ {print $2}') == "sysadmin" ]]; then
    msg_ok "Only sysadmin module left, which is required for Firewall, skipping removal"
  else
    msg_warn "Some commercial modules could not be removed, please check the web interface for removal manually!"
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
