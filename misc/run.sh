#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
#
# Remote fork/branch runner — sets COMMUNITY_SCRIPTS_URL once, then runs a CT script
# from that same base (so build.func / install/ all follow the fork).
#
# Usage:
#   curl -fsSL <base>/misc/run.sh | bash -s -- <base> ct/debian.sh
#
# Example (GitHub fork + feature branch):
#   BASE=https://raw.githubusercontent.com/YOU/ProxmoxVED/feat-branch
#   curl -fsSL "$BASE/misc/run.sh" | bash -s -- "$BASE" ct/debian.sh
#
# Local checkout (preferred, zero config):
#   bash ct/debian.sh
#
set -euo pipefail

BASE="${1:-}"
SCRIPT="${2:-}"

if [[ -z "$BASE" || -z "$SCRIPT" ]]; then
  echo "Usage: curl -fsSL <base>/misc/run.sh | bash -s -- <base> <script>" >&2
  echo "  e.g. bash -s -- https://raw.githubusercontent.com/YOU/ProxmoxVED/branch ct/debian.sh" >&2
  exit 2
fi

# Normalize
BASE="${BASE%/}"
SCRIPT="${SCRIPT#./}"

export COMMUNITY_SCRIPTS_URL="$BASE"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

echo "Community Scripts origin: ${COMMUNITY_SCRIPTS_URL}" >&2
echo "Running: ${SCRIPT}" >&2
bash -c "$(curl -fsSL "${COMMUNITY_SCRIPTS_URL}/${SCRIPT}")"
