#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: rtgibbons
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://linux.dell.com/repo/community/openmanage/

load_functions

APP="Dell OpenManage"

header_info "$APP"

install_ipmitool() {
    msg_info "Installing ipmitool"
    apt update &> /dev/null || msg_error
    apt install -y ipmitool &> /dev/null || msg_error
    msg_ok "Installed ipmitool"
}

get_idrac_version() {
    local IDRAC_VERSION
    IDRAC_VERSION=$(ipmitool sdr elist mcloc | cut -c6)
    echo "$IDRAC_VERSION"
}


install_sources() {
    msg_info "Installing Dell OpenManage repository"

    msg_info "Adding GPG keys"
    rm -f /etc/apt/trusted.gpg.d/dell-apt-key.gpg
    curl -sSL https://linux.dell.com/repo/pgp_pubkeys/0x1285491434D8786F.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/dell-apt-key.gpg

    msg_info "Adding Dell provided repos"
    cat<<EOF >/etc/apt/sources.list.d/dell-openmanage.sources
Types: deb
URIs: http://linux.dell.com/repo/community/openmanage/11000/jammy/
Suites: jammy
Components: main
Signed-By: /etc/apt/trusted.gpg.d/dell-apt-key.gpg

Types: deb
URIs: http://linux.dell.com/repo/community/openmanage/iSM/5400/bullseye/
Suites: bullseye
Components: main
EOF

    msg_info "Adding debian bullseye for dependencies"
    cat<<EOF >/etc/apt/sources.list.d/debian-bullseye.sources
Types: deb
URIs: http://deb.debian.org/debian/
Suites: bullseye
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

    msg_info "Setting package pinning for dell-openmanage"
    mkdir -p /etc/apt/preferences.d

    cat<<EOF >/etc/apt/preferences.d/debian-bullseye.pref
Package: *
Pin: release n=bullseye
Pin-Priority: -1
EOF

    cat<<EOF >/etc/apt/preferences.d/libssl1.1.pref
Package: libssl1.1
Pin: release n=bullseye
Pin-Priority: 500
EOF

    cat<<EOF >/etc/apt/preferences.d/dell-openmanage.pref
Package: *
Pin: origin linux.dell.com
Pin-Priority: 500
EOF
    msg_ok "Apt sources configure for Dell OpenManage installation"
}

install() {
    install_sources

    local IDRAC_VERSION
    IDRAC_VERSION=$(get_idrac_version)
    if [[ -n "$IDRAC_VERSION" && ($IDRAC_VERSION == 7 || $IDRAC_VERSION == 8) ]]; then
        msg_info "iDRAC version $IDRAC_VERSION detected"
    else
        msg_error "supported iDRAC not detected, exiting"
        exit 1
    fi

    msg_info "Installing Dell iDRAC and iSM tools"
    apt update &> /dev/null || msg_error
    apt install -y srvadmin-idracadm"$IDRAC_VERSION" dcism &> /dev/null || msg_error
    msg_ok "Installed Dell iDRAC and iSM tools"
}

load_services() {
    msg_info "Enabling and starting dell services"
    systemctl enable --now dcismeng.service &> /dev/null || msg_error
    msg_ok "Enabled and started dell services"
}

main() {
    pve_check
    root_check
    install_ipmitool
    install
    load_services
}

main
