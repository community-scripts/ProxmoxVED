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
$STD apt-get install -y curl
$STD apt-get install -y sudo
$STD apt-get install -y jq
msg_ok "Installed Dependencies"

msg_info "Check GH Releases"
echo "Getting 0xERR0R/blocky..."
RELEASE=$(get_gh_release 0xERR0R/blocky) || exit 1
echo "Got Version: $RELEASE"

echo "Getting aceberg/WatchYourLAN..."
RELEASE=$(get_gh_release aceberg/WatchYourLAN) || exit 1
echo "Got Version: $RELEASE"

echo "Getting actualbudget/actual-server..."
RELEASE=$(get_gh_release actualbudget/actual-server) || exit 1
echo "Got Version: $RELEASE"

echo "Getting agl/jbig2enc..."
RELEASE=$(get_gh_release agl/jbig2enc) || exit 1
echo "Got Version: $RELEASE"

echo "Getting alexta69/metube..."
RELEASE=$(get_gh_release alexta69/metube) || exit 1
echo "Got Version: $RELEASE"

echo "Getting AlexxIT/go2rtc..."
RELEASE=$(get_gh_release AlexxIT/go2rtc) || exit 1
echo "Got Version: $RELEASE"

echo "Getting apache/tika..."
RELEASE=$(get_gh_release apache/tika) || exit 1
echo "Got Version: $RELEASE"

echo "Getting ArtifexSoftware/ghostpdl-downloads..."
RELEASE=$(get_gh_release ArtifexSoftware/ghostpdl-downloads) || exit 1
echo "Got Version: $RELEASE"

echo "Getting Athou/commafeed..."
RELEASE=$(get_gh_release Athou/commafeed) || exit 1
echo "Got Version: $RELEASE"

echo "Getting authelia/authelia..."
RELEASE=$(get_gh_release authelia/authelia) || exit 1
echo "Got Version: $RELEASE"

echo "Getting azukaar/Cosmos-Server..."
RELEASE=$(get_gh_release azukaar/Cosmos-Server) || exit 1
echo "Got Version: $RELEASE"

echo "Getting bastienwirtz/homer..."
RELEASE=$(get_gh_release bastienwirtz/homer) || exit 1
echo "Got Version: $RELEASE"

echo "Getting benjaminjonard/koillection..."
RELEASE=$(get_gh_release benjaminjonard/koillection) || exit 1
echo "Got Version: $RELEASE"

echo "Getting benzino77/tasmocompiler..."
RELEASE=$(get_gh_release benzino77/tasmocompiler) || exit 1
echo "Got Version: $RELEASE"

echo "Getting blakeblackshear/frigate..."
RELEASE=$(get_gh_release blakeblackshear/frigate) || exit 1
echo "Got Version: $RELEASE"

echo "Getting bluenviron/mediamtx..."
RELEASE=$(get_gh_release bluenviron/mediamtx) || exit 1
echo "Got Version: $RELEASE"

echo "Getting BookStackApp/BookStack..."
RELEASE=$(get_gh_release BookStackApp/BookStack) || exit 1
echo "Got Version: $RELEASE"

echo "Getting browserless/chrome..."
RELEASE=$(get_gh_release browserless/chrome) || exit 1
echo "Got Version: $RELEASE"

echo "Getting Bubka/2FAuth..."
RELEASE=$(get_gh_release Bubka/2FAuth) || exit 1
echo "Got Version: $RELEASE"

echo "Getting caddyserver/xcaddy..."
RELEASE=$(get_gh_release caddyserver/xcaddy) || exit 1
echo "Got Version: $RELEASE"

echo "Getting clusterzx/paperless-ai..."
RELEASE=$(get_gh_release clusterzx/paperless-ai) || exit 1
echo "Got Version: $RELEASE"

echo "Getting cockpit-project/cockpit..."
RELEASE=$(get_gh_release cockpit-project/cockpit) || exit 1
echo "Got Version: $RELEASE"

echo "Getting community-scripts/ProxmoxVE..."
RELEASE=$(get_gh_release community-scripts/ProxmoxVE) || exit 1
echo "Got Version: $RELEASE"

echo "Getting CorentinTh/it-tools..."
RELEASE=$(get_gh_release CorentinTh/it-tools) || exit 1
echo "Got Version: $RELEASE"

echo "Getting dani-garcia/bw_web_builds..."
RELEASE=$(get_gh_release dani-garcia/bw_web_builds) || exit 1
echo "Got Version: $RELEASE"

msg_ok "Done"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
