#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y jq
msg_ok "Installed Dependencies"

# echo "Getting aceberg/WatchYourLAN..."
# fetch_and_deploy_gh_release aceberg/WatchYourLAN
# echo "Got Version: $RELEASE"

# echo "Getting actualbudget/actual..."
# RELEASE=$(get_gh_release actualbudget/actual)
# echo "Got Version: $RELEASE"

# echo "Getting agl/jbig2enc..."
# RELEASE=$(get_gh_release agl/jbig2enc)
# echo "Got Version: $RELEASE"

# echo "Getting alexta69/metube..."
# RELEASE=$(get_gh_release alexta69/metube)
# echo "Got Version: $RELEASE"

# echo "Getting AlexxIT/go2rtc..."
# RELEASE=$(get_gh_release AlexxIT/go2rtc)
# echo "Got Version: $RELEASE"

# echo "Getting apache/tika..."
# RELEASE=$(get_gh_release apache/tika)
# echo "Got Version: $RELEASE"

# echo "Getting ArtifexSoftware/ghostpdl-downloads..."
# RELEASE=$(get_gh_release ArtifexSoftware/ghostpdl-downloads)
# echo "Got Version: $RELEASE"

# echo "Getting Athou/commafeed..."
# RELEASE=$(get_gh_release Athou/commafeed)
# echo "Got Version: $RELEASE"

# echo "Getting authelia/authelia..."
# RELEASE=$(get_gh_release authelia/authelia)
# echo "Got Version: $RELEASE"

# echo "Getting azukaar/Cosmos-Server..."
# RELEASE=$(get_gh_release azukaar/Cosmos-Server)
# echo "Got Version: $RELEASE"

# echo "Getting bastienwirtz/homer..."
# RELEASE=$(get_gh_release bastienwirtz/homer)
# echo "Got Version: $RELEASE"

# echo "Getting benjaminjonard/koillection..."
# RELEASE=$(get_gh_release benjaminjonard/koillection)
# echo "Got Version: $RELEASE"

# echo "Getting benzino77/tasmocompiler..."
# RELEASE=$(get_gh_release benzino77/tasmocompiler)
# echo "Got Version: $RELEASE"

# echo "Getting blakeblackshear/frigate..."
# RELEASE=$(get_gh_release blakeblackshear/frigate)
# echo "Got Version: $RELEASE"

# echo "Getting bluenviron/mediamtx..."
# RELEASE=$(get_gh_release bluenviron/mediamtx)
# echo "Got Version: $RELEASE"

# echo "Getting BookStackApp/BookStack..."
# RELEASE=$(get_gh_release BookStackApp/BookStack)
# echo "Got Version: $RELEASE"

# echo "Getting browserless/chrome..."
# RELEASE=$(get_gh_release browserless/chrome)
# echo "Got Version: $RELEASE"

# echo "Getting Bubka/2FAuth..."
# RELEASE=$(get_gh_release Bubka/2FAuth)
# echo "Got Version: $RELEASE"

# echo "Getting caddyserver/xcaddy..."
# RELEASE=$(get_gh_release caddyserver/xcaddy)
# echo "Got Version: $RELEASE"

# echo "Getting clusterzx/paperless-ai..."
# RELEASE=$(get_gh_release clusterzx/paperless-ai)
# echo "Got Version: $RELEASE"

# echo "Getting cockpit-project/cockpit..."
# RELEASE=$(get_gh_release cockpit-project/cockpit)
# echo "Got Version: $RELEASE"

# echo "Getting community-scripts/ProxmoxVE..."
# RELEASE=$(get_gh_release community-scripts/ProxmoxVE)
# echo "Got Version: $RELEASE"

# echo "Getting CorentinTh/it-tools..."
# RELEASE=$(get_gh_release CorentinTh/it-tools)
# echo "Got Version: $RELEASE"

# echo "Getting dani-garcia/bw_web_builds..."
# RELEASE=$(get_gh_release dani-garcia/bw_web_builds)
# echo "Got Version: $RELEASE"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
