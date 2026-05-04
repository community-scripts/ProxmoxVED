#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: dooha333
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/qwibitai/nanoclaw

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_hwaccel

msg_info "Installing dependencies"
$STD apt-get install -y \
  sudo \
  ca-certificates \
  curl \
  git \
  acl \
  build-essential
# acl provides setfacl, used by setup/service.ts as a fallback when the
# docker group membership isn't yet active in the current login session.
# build-essential gives us make/gcc/g++ — node-gyp needs them to compile
# better-sqlite3 (and other native pnpm deps) from source during the
# wizard's `pnpm install` step.
# polkitd ships /usr/bin/pkttyagent. Without it, loginctl/systemctl calls
# that go through DBus print "Failed to execute /usr/bin/pkttyagent" — the
# action still succeeds, but the noise looks like a failure mid-setup.
# Package was renamed in Debian 13 (Trixie); fall back to the Bookworm name.
$STD apt-get install -y polkitd || $STD apt-get install -y policykit-1
msg_ok "Installed dependencies"

msg_info "Creating nanoclaw user"
useradd -m -s /bin/bash nanoclaw
# Blanket NOPASSWD: the wizard at ~/nanoclaw-v2/nanoclaw.sh runs unattended
# and needs sudo for apt, systemctl, docker group setup, and polkit calls
# that would otherwise hang on a TTY prompt. Scope is acceptable here —
# nanoclaw is the single-tenant operator user and this LXC is not multi-user.
echo "nanoclaw ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/nanoclaw
chmod 440 /etc/sudoers.d/nanoclaw
loginctl enable-linger nanoclaw
# Ensure ~/.local/bin is on PATH for every new shell. Debian's default skel
# .bashrc only adds it when the directory already exists at sourcing time —
# but ~/.local/bin doesn't exist until the wizard installs Claude CLI / pnpm
# bins into it, so without this users see "claude: command not found" on
# every login until they edit .bashrc themselves.
if ! grep -q '\.local/bin' /home/nanoclaw/.bashrc 2>/dev/null; then
  printf '\n# Added by nanoclaw LXC install — ~/.local/bin holds claude, pnpm globals, etc.\nexport PATH="$HOME/.local/bin:$PATH"\n' >>/home/nanoclaw/.bashrc
  chown nanoclaw:nanoclaw /home/nanoclaw/.bashrc
fi
msg_ok "Created nanoclaw user"

msg_info "Installing SSH key for nanoclaw"
# build.func exports SSH_AUTHORIZED_KEY with the pasted key, but only writes
# it to /root/.ssh/authorized_keys when SSH-on-root is enabled. We want the
# nanoclaw user to get the key even when root SSH stays disabled (the safer
# default), so read the exported var directly. Fall back to the root file in
# case the framework already wrote it for us.
NANOCLAW_SSH_KEY=""
if [[ -n "${SSH_AUTHORIZED_KEY:-}" ]]; then
  NANOCLAW_SSH_KEY="$SSH_AUTHORIZED_KEY"
elif [[ -s /root/.ssh/authorized_keys ]]; then
  NANOCLAW_SSH_KEY="$(cat /root/.ssh/authorized_keys)"
fi
if [[ -n "$NANOCLAW_SSH_KEY" ]]; then
  install -d -o nanoclaw -g nanoclaw -m 700 /home/nanoclaw/.ssh
  printf '%s\n' "$NANOCLAW_SSH_KEY" >/home/nanoclaw/.ssh/authorized_keys
  chown nanoclaw:nanoclaw /home/nanoclaw/.ssh/authorized_keys
  chmod 600 /home/nanoclaw/.ssh/authorized_keys
  msg_ok "Installed SSH key for nanoclaw"
else
  msg_ok "No SSH key supplied (skipping)"
fi

# Single source of truth for what we clone and where. If you change the URL,
# also update the `# Source:` header at the top of this file (it's project-home
# documentation, not auto-derived from this variable).
NANOCLAW_REPO="https://github.com/qwibitai/nanoclaw.git"
NANOCLAW_DIR="/home/nanoclaw/nanoclaw-v2"
NANOCLAW_DIR_BASENAME="$(basename "$NANOCLAW_DIR")"

msg_info "Cloning NanoClaw from ${NANOCLAW_REPO}"
$STD sudo -u nanoclaw -H git clone "$NANOCLAW_REPO" "$NANOCLAW_DIR"
msg_ok "Cloned NanoClaw from ${NANOCLAW_REPO} into ${NANOCLAW_DIR}"

motd_ssh

# Write our MOTD AFTER motd_ssh — motd_ssh runs `chmod -x /etc/update-motd.d/*`
# (install.func:1125) which would otherwise disable our file by removing the
# executable bit Debian's update-motd framework requires.
msg_info "Writing setup MOTD"
cat >/etc/update-motd.d/99-nanoclaw <<EOF
#!/bin/sh
cat <<MOTD

  NanoClaw is staged at ${NANOCLAW_DIR}

  Finish setup:
    su - nanoclaw
    cd ~/${NANOCLAW_DIR_BASENAME}
    bash nanoclaw.sh

  The wizard installs Node, pnpm, Docker, sets up the OneCLI vault,
  prompts for your Anthropic API key (or 'subscription' for Claude
  Code login), and starts the host service.

MOTD
EOF
chmod +x /etc/update-motd.d/99-nanoclaw
msg_ok "Wrote setup MOTD"

customize
cleanup_lxc
