# Install.func Wiki

Container installation workflow orchestration module providing network setup, OS configuration, connectivity verification, and installation mechanics for applications deployed inside LXC containers.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Initialization & Dependencies](#initialization--dependencies)
- [Network & Connectivity Functions](#network--connectivity-functions)
- [OS Configuration Functions](#os-configuration-functions)
- [Installation Workflow](#installation-workflow)
- [Best Practices](#best-practices)
- [Debugging](#debugging)
- [Contributing](#contributing)

---

## Overview

Install.func provides **container-internal installation mechanics**:

- ✅ Network connectivity verification (IPv4/IPv6)
- ✅ OS updates and package management
- ✅ DNS resolution validation
- ✅ System optimization (disable wait-online service)
- ✅ SSH and MOTD configuration
- ✅ Container customization (auto-login, update script)
- ✅ Comprehensive error handling with signal traps
- ✅ Integration with core.func and error_handler.func

### Execution Context

```
Proxmox Host                LXC Container
──────────────────────────────────────────
pct create CTID ...
    ↓
Boot container
    ↓
pct exec CTID bash /tmp/install.sh
    ↓
[Execution within container]
    └─→ install.func functions execute
        └─→ verb_ip6()
        └─→ setting_up_container()
        └─→ network_check()
        └─→ update_os()
        └─→ etc.
```

---

## Initialization & Dependencies

### Module Dependencies

```bash
# Install.func requires two prerequisites
if ! command -v curl >/dev/null 2>&1; then
  apt-get update >/dev/null 2>&1
  apt-get install -y curl >/dev/null 2>&1
fi

# Source core functions (colors, formatting, messages)
source <(curl -fsSL https://git.community-scripts.org/.../core.func)

# Source error handling (traps, signal handlers)
source <(curl -fsSL https://git.community-scripts.org/.../error_handler.func)

# Initialize both modules
load_functions      # Sets up colors, icons, defaults
catch_errors        # Configures ERR, EXIT, INT, TERM traps
```

### Environment Variables Passed from Host

These variables are passed by build.func via `pct set` and environment:

| Variable | Source | Purpose |
|----------|--------|---------|
| `VERBOSE` | Build config | Show all output (yes/no) |
| `PASSWORD` | User input | Root password (blank = auto-login) |
| `DISABLEIPV6` | Advanced settings | Disable IPv6 (yes/no) |
| `SSH_ROOT` | Advanced settings | Enable SSH root access |
| `CACHER` | Config | Use APT cache proxy (yes/no) |
| `CACHER_IP` | Config | APT cache IP address |
| `APPLICATION` | App script | App display name |
| `app` | App script | Normalized app name (lowercase) |
| `RETRY_NUM` | core.func | Retry attempts (default: 10) |
| `RETRY_EVERY` | core.func | Retry interval in seconds (default: 3) |

---

## Network & Connectivity Functions

### `verb_ip6()`

**Purpose**: Configures IPv6 based on DISABLEIPV6 variable and sets verbose mode.

**Signature**:
```bash
verb_ip6()
```

**Parameters**: None

**Returns**: No explicit return value (configures system)

**Environment Requirements**:
- `DISABLEIPV6` - Set to "yes" to disable IPv6, "no" to keep enabled
- `VERBOSE` - Controls output verbosity via set_std_mode()

**Behavior**:
```bash
# If DISABLEIPV6=yes:
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
sysctl -p  # Apply immediately

# If DISABLEIPV6=no (default):
# No changes (IPv6 remains enabled)
```

**Usage Examples**:

```bash
# Example 1: Disable IPv6 (for security/simplicity)
DISABLEIPV6="yes"
VERBOSE="no"
verb_ip6
# Result: IPv6 disabled, change persisted

# Example 2: Keep IPv6 enabled (default)
DISABLEIPV6="no"
verb_ip6
# Result: IPv6 operational, no configuration

# Example 3: Verbose mode
VERBOSE="yes"
verb_ip6
# Output: Shows sysctl configuration commands
```

---

### `setting_up_container()`

**Purpose**: Verifies network connectivity and performs initial OS configuration for Debian/Ubuntu containers.

**Signature**:
```bash
setting_up_container()
```

**Parameters**: None

**Returns**: 0 on success; exits with code 1 if network unavailable after retries

**Environment Requirements**:
- `RETRY_NUM` - Max attempts (default: 10)
- `RETRY_EVERY` - Seconds between retries (default: 3)

**Operations**:
1. Verify network connectivity via `hostname -I`
2. Retry up to RETRY_NUM times with RETRY_EVERY second delays
3. Remove Python EXTERNALLY-MANAGED marker (allows pip)
4. Disable systemd-networkd-wait-online.service (speeds up boot)
5. Display network information

**Implementation Pattern**:
```bash
setting_up_container() {
  msg_info "Setting up Container OS"

  # Network availability loop
  for ((i = RETRY_NUM; i > 0; i--)); do
    if [ "$(hostname -I)" != "" ]; then
      break
    fi
    echo 1>&2 -en "${CROSS}${RD} No Network! "
    sleep $RETRY_EVERY
  done

  # Check final state
  if [ "$(hostname -I)" = "" ]; then
    echo 1>&2 -e "\n${CROSS}${RD} No Network After $RETRY_NUM Tries${CL}"
    exit 1
  fi

  # Python pip support
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED

  # Speed up boot (disable wait service)
  systemctl disable -q --now systemd-networkd-wait-online.service

  msg_ok "Set up Container OS"
  msg_ok "Network Connected: ${BL}$(hostname -I)${CL}"
}
```

**Usage Examples**:

```bash
# Example 1: Immediate network availability
RETRY_NUM=10
RETRY_EVERY=3
setting_up_container
# Output:
# ℹ️  Setting up Container OS
# ✔️  Set up Container OS
# ✔️  Network Connected: 10.0.3.50

# Example 2: Delayed network (waits 6 seconds)
# Script retries 2 times before succeeding
# (each retry waits 3 seconds)

# Example 3: No network
# Script waits 30 seconds total (10 x 3)
# Then exits with: "No Network After 10 Tries"
```

---

### `network_check()`

**Purpose**: Comprehensive network diagnostics for both IPv4 and IPv6, including DNS validation for Git/GitHub.

**Signature**:
```bash
network_check()
```

**Parameters**: None

**Returns**: 0 on success; exits with code 1 on critical DNS failure

**Checks Performed**:

1. **IPv4 Connectivity** (tests 3 public DNS servers):
   - 1.1.1.1 (Cloudflare)
   - 8.8.8.8 (Google)
   - 9.9.9.9 (Quad9)

2. **IPv6 Connectivity** (tests 3 public DNS servers):
   - 2606:4700:4700::1111 (Cloudflare)
   - 2001:4860:4860::8888 (Google)
   - 2620:fe::fe (Quad9)

3. **DNS Resolution** (validates Git-related domains):
   - github.com
   - raw.githubusercontent.com
   - api.github.com
   - git.community-scripts.org

**Output Format**:
```
✔️  IPv4 Internet Connected
✔️  IPv6 Internet Connected
✔️  Git DNS: github.com:✔️ raw.githubusercontent.com:✔️ ...
```

**Error Handling**:
```bash
# If both IPv4 and IPv6 fail:
# Prompts user: "No Internet detected, would you like to continue anyway?"
# If user says no: Exits
# If user says yes: Shows warning "Expect Issues Without Internet"

# If DNS fails for GitHub:
# Calls fatal() - exits immediately with error
```

**Implementation Pattern**:
```bash
network_check() {
  set +e
  trap - ERR

  ipv4_connected=false
  ipv6_connected=false

  # IPv4 test
  if ping -c 1 -W 1 1.1.1.1 &>/dev/null || ...; then
    msg_ok "IPv4 Internet Connected"
    ipv4_connected=true
  else
    msg_error "IPv4 Internet Not Connected"
  fi

  # IPv6 test
  if ping6 -c 1 -W 1 2606:4700:4700::1111 &>/dev/null || ...; then
    msg_ok "IPv6 Internet Connected"
    ipv6_connected=true
  else
    msg_error "IPv6 Internet Not Connected"
  fi

  # DNS checks for GitHub domains
  GIT_HOSTS=("github.com" "raw.githubusercontent.com" "api.github.com" "git.community-scripts.org")
  for HOST in "${GIT_HOSTS[@]}"; do
    RESOLVEDIP=$(getent hosts "$HOST" | awk '{ print $1 }' | head -n1)
    if [[ -z "$RESOLVEDIP" ]]; then
      DNS_FAILED=true
    fi
  done

  if [[ "$DNS_FAILED" == true ]]; then
    fatal "$GIT_STATUS"  # Exit on critical DNS failure
  fi

  set -e
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}
```

**Usage Examples**:

```bash
# Example 1: Good connectivity (all checks pass)
network_check
# Output:
# ✔️  IPv4 Internet Connected
# ✔️  IPv6 Internet Connected
# ✔️  Git DNS: github.com:✔️ ...

# Example 2: IPv6 unavailable but IPv4 OK
network_check
# Output:
# ✔️  IPv4 Internet Connected
# ✖️  IPv6 Internet Not Connected
# ✔️  Git DNS checks OK

# Example 3: No internet at all
network_check
# Prompts: "No Internet detected, would you like to continue anyway?"
# User: y
# Output: ⚠️  Expect Issues Without Internet
```

---

## OS Configuration Functions

### `update_os()`

**Purpose**: Updates Debian/Ubuntu OS packages and loads additional tools library.

**Signature**:
```bash
update_os()
```

**Parameters**: None

**Returns**: No explicit return value (updates system)

**Operations**:
1. Display info message
2. Optional: Configure APT caching proxy
3. Run `apt-get update` (index refresh)
4. Run `apt-get dist-upgrade` (system upgrade)
5. Remove Python EXTERNALLY-MANAGED restrictions
6. Source tools.func for additional setup
7. Display success message

**APT Caching Configuration** (if CACHER=yes):
```bash
# Configure apt-proxy-detect.sh
/etc/apt/apt.conf.d/00aptproxy

# Script detects local APT cacher and routes through it
# Falls back to DIRECT if unavailable
```

**Implementation Pattern**:
```bash
update_os() {
  msg_info "Updating Container OS"

  # Optional: Setup APT cacher
  if [[ "$CACHER" == "yes" ]]; then
    echo "Acquire::http::Proxy-Auto-Detect \"/usr/local/bin/apt-proxy-detect.sh\";" > /etc/apt/apt.conf.d/00aptproxy

    cat > /usr/local/bin/apt-proxy-detect.sh <<'EOF'
#!/bin/bash
if nc -w1 -z "${CACHER_IP}" 3142; then
  echo -n "http://${CACHER_IP}:3142"
else
  echo -n "DIRECT"
fi
EOF
    chmod +x /usr/local/bin/apt-proxy-detect.sh
  fi

  # Update system
  $STD apt-get update
  $STD apt-get -o Dpkg::Options::="--force-confold" -y dist-upgrade

  # Python support
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED

  # Load additional tools library
  source <(curl -fsSL https://git.community-scripts.org/.../tools.func)

  msg_ok "Updated Container OS"
}
```

**Usage Examples**:

```bash
# Example 1: Standard update
update_os
# Output: Updates all packages silently (unless VERBOSE=yes)

# Example 2: With APT cacher
CACHER="yes"
CACHER_IP="192.168.1.100"
update_os
# Uses cache proxy for faster package downloads

# Example 3: Verbose output
VERBOSE="yes"
update_os
# Shows all apt-get operations in detail
```

---

## SSH & MOTD Configuration

### `motd_ssh()`

**Purpose**: Configures Message of the Day and enables SSH root access if configured.

**Signature**:
```bash
motd_ssh()
```

**Parameters**: None

**Returns**: No explicit return value (configures system)

**Operations**:
1. Set TERM environment variable for better terminal support
2. Gather OS information (name, version, IP)
3. Create `/etc/profile.d/00_lxc-details.sh` with container details script
4. Optionally enable root SSH access if SSH_ROOT=yes

**MOTD Script Content**:
```bash
echo -e ""
echo -e "${BOLD}${YW}${APPLICATION} LXC Container - DEV Repository${CL}"
echo -e "${RD}WARNING: This is a DEVELOPMENT version (ProxmoxVED). Do NOT use in production!${CL}"
echo -e "${YW} OS: ${GN}${OS_NAME} - Version: ${OS_VERSION}${CL}"
echo -e "${YW} Hostname: ${GN}$(hostname)${CL}"
echo -e "${YW} IP Address: ${GN}$(hostname -I | awk '{print $1}')${CL}"
echo -e "${YW} Repository: ${GN}https://github.com/community-scripts/ProxmoxVED${CL}"
echo ""
```

**SSH Configuration** (if SSH_ROOT=yes):
```bash
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/g" /etc/ssh/sshd_config
systemctl restart sshd
```

---

## Installation Workflow

### Typical Installation Sequence

```bash
#!/bin/bash
# Inside container during installation

source <(curl -fsSL .../core.func)
source <(curl -fsSL .../error_handler.func)
load_functions
catch_errors

# Step 1: Network setup
verb_ip6
setting_up_container
network_check

# Step 2: System update
update_os

# Step 3: SSH and MOTD
motd_ssh

# Step 4: Install application (app-specific)
# ... application installation steps ...

# Step 5: Create update script
customize
```

---

## Best Practices

### 1. **Always Initialize First**

```bash
#!/bin/bash
set -Eeuo pipefail

if ! command -v curl >/dev/null 2>&1; then
  apt-get update >/dev/null 2>&1
  apt-get install -y curl >/dev/null 2>&1
fi

source <(curl -fsSL .../core.func)
source <(curl -fsSL .../error_handler.func)
load_functions
catch_errors
```

### 2. **Check Network Early**

```bash
setting_up_container    # Verify network available
network_check          # Validate connectivity and DNS
update_os              # Proceed with updates

# If network fails, exit immediately
# Don't waste time on installation
```

### 3. **Use Retry Logic**

```bash
# Built into setting_up_container():
for ((i = RETRY_NUM; i > 0; i--)); do
  if [ "$(hostname -I)" != "" ]; then
    break
  fi
  sleep $RETRY_EVERY
done

# Tolerates temporary network delay
```

### 4. **Separate Concerns**

```bash
# Network setup
verb_ip6
setting_up_container
network_check

# System updates
update_os

# Configuration
motd_ssh

# Application-specific
# ... app installation ...
```

### 5. **Capture Environment**

```bash
# Pass these from build.func:
VERBOSE="yes"              # Show all output
DISABLEIPV6="no"           # Keep IPv6
SSH_ROOT="yes"             # Enable SSH
APPLICATION="Jellyfin"     # App name
CACHER="no"                # No APT cache
```

---

## Debugging

### Enable Verbose Output

```bash
VERBOSE="yes" pct exec CTID bash /tmp/install.sh
# Shows all commands and output
```

### Check Network Status Inside Container

```bash
pct exec CTID hostname -I
pct exec CTID ping -c 1 1.1.1.1
pct exec CTID getent hosts github.com
```

### View Installation Log

```bash
# From container
cat /root/install-*.log

# Or from host (if logs mounted)
tail -100 /var/log/community-scripts/install-*.log
```

---

## Contributing

### Adding New Network Checks

```bash
network_check() {
  # ... existing checks ...

  # Add new check:
  if ! getent hosts newhost.example.com &>/dev/null; then
    msg_warn "Unable to resolve newhost.example.com"
  fi
}
```

### Extending OS Configuration

```bash
# Add to update_os():
update_os() {
  # ... existing updates ...

  # Add new capability:
  $STD apt-get install -y some-package
  msg_ok "Additional package installed"
}
```

---

## Notes

- Install.func executes **inside the container** (not on Proxmox host)
- Network connectivity is **critical** - checked early and thoroughly
- OS updates are **required** before application installation
- IPv6 is **configurable** but enabled by default
- SSH and MOTD are **informational** - help with container management

