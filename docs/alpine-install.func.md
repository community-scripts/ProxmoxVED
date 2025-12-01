# Alpine-Install.func Wiki

A specialized module for Alpine Linux LXC container setup and configuration, providing functions for IPv6 management, network verification, OS updates, SSH configuration, timezone validation, and passwordless auto-login customization.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Initialization & Signal Handling](#initialization--signal-handling)
- [Network & Connectivity Functions](#network--connectivity-functions)
- [OS Configuration Functions](#os-configuration-functions)
- [SSH & MOTD Configuration](#ssh--motd-configuration)
- [Container Customization](#container-customization)
- [Best Practices](#best-practices)
- [Error Handling](#error-handling)
- [Contributing](#contributing)

---

## Overview

This module provides Alpine Linux-specific installation and configuration functions used inside LXC containers during the setup phase. Key capabilities include:

- ✅ IPv6 enablement/disablement with persistent configuration
- ✅ Network connectivity verification with retry logic
- ✅ Alpine Linux OS updates via apk package manager
- ✅ SSH daemon and MOTD configuration
- ✅ Passwordless root auto-login setup
- ✅ Timezone validation for Alpine containers
- ✅ Comprehensive error handling with signal traps

### Integration Pattern

```bash
# Alpine container scripts load this module via curl
source <(curl -fsSL https://git.community-scripts.org/.../alpine-install.func)
load_functions      # Initialize core utilities
catch_errors        # Setup error handling and signal traps
```

---

## Initialization & Signal Handling

### Module Dependencies

The module automatically sources two required dependencies:

```bash
source <(curl -fsSL .../core.func)           # Color codes, icons, message functions
source <(curl -fsSL .../error_handler.func)  # Error handling and exit codes
load_functions                                # Initialize color/formatting
catch_errors                                  # Setup trap handlers
```

### Signal Trap Configuration

```bash
set -Eeuo pipefail                            # Strict error mode
trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR
trap on_exit EXIT                             # Cleanup on exit
trap on_interrupt INT                         # Handle Ctrl+C (SIGINT)
trap on_terminate TERM                        # Handle SIGTERM
```

---

## Network & Connectivity Functions

### `verb_ip6()`

**Purpose**: Configures IPv6 settings and sets verbose mode based on environment variables.

**Signature**:
```bash
verb_ip6()
```

**Parameters**: None

**Returns**: No explicit return value (configures system state)

**Environment Effects**:
- Sets `STD` variable to control output verbosity (via `set_std_mode()`)
- If `DISABLEIPV6=yes`: disables IPv6 system-wide via sysctl
- Modifies `/etc/sysctl.conf` for persistent IPv6 disabled state

**Implementation Pattern**:
```bash
verb_ip6() {
  set_std_mode  # Initialize STD="" or STD="silent"

  if [ "$DISABLEIPV6" == "yes" ]; then
    $STD sysctl -w net.ipv6.conf.all.disable_ipv6=1
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >>/etc/sysctl.conf
    $STD rc-update add sysctl default
  fi
}
```

**Usage Examples**:

```bash
# Example 1: With IPv6 disabled
DISABLEIPV6="yes"
VERBOSE="no"
verb_ip6
# Result: IPv6 disabled, changes persisted to sysctl.conf

# Example 2: Keep IPv6 enabled (default)
DISABLEIPV6="no"
verb_ip6
# Result: IPv6 remains enabled, no configuration changes
```

---

### `setting_up_container()`

**Purpose**: Verifies network connectivity by checking for assigned IP addresses and retrying if necessary.

**Signature**:
```bash
setting_up_container()
```

**Parameters**: None (uses global `RETRY_NUM` and `RETRY_EVERY`)

**Returns**: 0 on success; exits with code 1 if network unavailable after retries

**Environment Side Effects**:
- Requires: `RETRY_NUM` (max attempts, default: 10), `RETRY_EVERY` (seconds between retries, default: 3)
- Uses: `CROSS`, `RD`, `CL`, `GN`, `BL` color variables from core.func
- Calls: `msg_info()`, `msg_ok()` message functions

**Implementation Pattern**:
```bash
setting_up_container() {
  msg_info "Setting up Container OS"
  i=$RETRY_NUM  # Use global counter
  while [ $i -gt 0 ]; do
    # Check for non-loopback IPv4 address
    if [ "$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | ...)" != "" ]; then
      break
    fi
    echo 1>&2 -en "${CROSS}${RD} No Network! "
    sleep $RETRY_EVERY
    i=$((i - 1))
  done

  # If still no network after retries, exit with error
  if [ "$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | ...)" = "" ]; then
    exit 1
  fi
  msg_ok "Network Connected: ${BL}$(ip addr show | grep 'inet ' | awk '{print $2}' | ...)${CL}"
}
```

**Usage Examples**:

```bash
# Example 1: Network available immediately
RETRY_NUM=10
RETRY_EVERY=3
setting_up_container
# Output:
# ℹ️  Setting up Container OS
# ✔️  Set up Container OS
# ✔️  Network Connected: 10.0.3.50

# Example 2: Network delayed by 6 seconds (2 retries)
# Script waits 3 seconds x 2, then succeeds
# Output shows retry messages, then success
```

---

### `network_check()`

**Purpose**: Comprehensive network connectivity verification for both IPv4 and IPv6, including DNS resolution checks for Git-related domains.

**Signature**:
```bash
network_check()
```

**Parameters**: None

**Returns**: 0 on success; exits with code 1 if DNS critical failure

**Environment Side Effects**:
- Temporarily disables error trap (`set +e`, `trap - ERR`)
- Modifies error handling to allow graceful failure detection
- Re-enables error trap at end of function
- Calls: `msg_ok()`, `msg_error()`, `fatal()` message functions

**Implementation Pattern**:
```bash
network_check() {
  set +e
  trap - ERR

  # Test IPv4 via multiple DNS servers
  if ping -c 1 -W 1 1.1.1.1 &>/dev/null || ...; then
    ipv4_status="${GN}✔${CL} IPv4"
  else
    ipv4_status="${RD}✖${CL} IPv4"
    # Prompt user to continue without internet
  fi

  # Verify DNS resolution for GitHub domains
  RESOLVEDIP=$(getent hosts github.com | awk '{ print $1 }')
  if [[ -z "$RESOLVEDIP" ]]; then
    msg_error "Internet: ${ipv4_status}  DNS Failed"
  else
    msg_ok "Internet: ${ipv4_status}  DNS: ${BL}${RESOLVEDIP}${CL}"
  fi

  set -e
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}
```

**Usage Examples**:

```bash
# Example 1: Good connectivity
network_check
# Output:
# ✔️  Network Connected: IPv4
# ✔️  Internet: ✔ IPv4  DNS: 140.82.113.3

# Example 2: No internet, user continues anyway
# Output prompts: "Internet NOT connected. Continue anyway? <y/N>"
# If user enters 'y':
# ⚠️  Expect Issues Without Internet
```

---

## OS Configuration Functions

### `update_os()`

**Purpose**: Updates Alpine Linux OS packages and installs Alpine-specific tools library for additional setup functions.

**Signature**:
```bash
update_os()
```

**Parameters**: None

**Returns**: No explicit return value (updates system)

**Environment Side Effects**:
- Runs `apk update && apk upgrade`
- Sources alpine-tools.func for Alpine-specific package installation helpers
- Uses `$STD` wrapper to suppress output unless `VERBOSE=yes`
- Calls: `msg_info()`, `msg_ok()` message functions

**Implementation Pattern**:
```bash
update_os() {
  msg_info "Updating Container OS"
  $STD apk update && $STD apk upgrade
  source <(curl -fsSL https://git.community-scripts.org/.../alpine-tools.func)
  msg_ok "Updated Container OS"
}
```

**Usage Examples**:

```bash
# Example 1: Standard update
VERBOSE="no"
update_os
# Output:
# ℹ️  Updating Container OS
# ✔️  Updated Container OS
# (Output suppressed via $STD)

# Example 2: Verbose mode
VERBOSE="yes"
update_os
# Output shows all apk operations plus success message
```

---

## SSH & MOTD Configuration

### `motd_ssh()`

**Purpose**: Configures Message of the Day (MOTD) with container information and enables SSH root access if required.

**Signature**:
```bash
motd_ssh()
```

**Parameters**: None

**Returns**: No explicit return value (configures system)

**Environment Side Effects**:
- Modifies `/root/.bashrc` to set TERM environment variable
- Creates `/etc/profile.d/00_lxc-details.sh` with container information script
- If `SSH_ROOT=yes`: modifies `/etc/ssh/sshd_config` and starts SSH daemon
- Uses: `APPLICATION`, `SSH_ROOT` variables from environment
- Requires: color variables (`BOLD`, `YW`, `RD`, `GN`, `CL`) from core.func

**Implementation Pattern**:
```bash
motd_ssh() {
  # Configure TERM for better terminal support
  echo "export TERM='xterm-256color'" >>/root/.bashrc

  # Gather OS information
  OS_NAME=$(grep ^NAME /etc/os-release | cut -d= -f2 | tr -d '"')
  OS_VERSION=$(grep ^VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '"')
  IP=$(ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)

  # Create MOTD script with container details
  PROFILE_FILE="/etc/profile.d/00_lxc-details.sh"
  cat > "$PROFILE_FILE" <<'EOF'
echo -e ""
echo -e "${BOLD}${YW}${APPLICATION} LXC Container - DEV Repository${CL}"
echo -e "${RD}WARNING: This is a DEVELOPMENT version (ProxmoxVED). Do NOT use in production!${CL}"
echo -e "${YW} OS: ${GN}${OS_NAME} - Version: ${OS_VERSION}${CL}"
echo -e "${YW} Hostname: ${GN}$(hostname)${CL}"
echo -e "${YW} IP Address: ${GN}${IP}${CL}"
echo -e "${YW} Repository: ${GN}https://github.com/community-scripts/ProxmoxVED${CL}"
echo ""
EOF

  # Enable SSH root access if configured
  if [[ "${SSH_ROOT}" == "yes" ]]; then
    sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/g" /etc/ssh/sshd_config
    rc-update add sshd
    /etc/init.d/sshd start
  fi
}
```

**Usage Examples**:

```bash
# Example 1: MOTD configuration with SSH enabled
APPLICATION="MyApp"
SSH_ROOT="yes"
motd_ssh
# Result: SSH daemon started and set to auto-start, MOTD shows app info

# Example 2: MOTD only (SSH disabled)
APPLICATION="MyApp"
SSH_ROOT="no"
motd_ssh
# Result: MOTD configured but SSH remains disabled
```

---

## Container Customization

### `validate_tz()`

**Purpose**: Validates that a timezone string exists in the Alpine Linux timezone database.

**Signature**:
```bash
validate_tz()
```

**Parameters**:
- `$1` - Timezone string (e.g., "America/New_York", "UTC", "Europe/London")

**Returns**: 0 if timezone file exists, 1 if invalid

**Implementation Pattern**:
```bash
validate_tz() {
  [[ -f "/usr/share/zoneinfo/$1" ]]  # Bash test operator returns success/failure
}
```

**Usage Examples**:

```bash
# Example 1: Valid timezone
validate_tz "America/New_York"
echo $?  # Output: 0

# Example 2: Invalid timezone
validate_tz "Invalid/Timezone"
echo $?  # Output: 1

# Example 3: UTC (always valid)
validate_tz "UTC"
echo $?  # Output: 0
```

---

### `customize()`

**Purpose**: Configures container for passwordless root auto-login and creates update script for easy application re-deployment.

**Signature**:
```bash
customize()
```

**Parameters**: None (uses global `PASSWORD` and `app` variables)

**Returns**: No explicit return value (configures system)

**Environment Side Effects**:
- If `PASSWORD=""` (empty):
  * Removes password prompt from root login
  * Drops user into shell automatically
  * Creates autologin boot script at `/etc/local.d/autologin.start`
  * Creates `.hushlogin` to suppress login banners
  * Registers script with rc-update
- Creates `/usr/bin/update` script for application updates
- Requires: `app` variable (application name in lowercase)
- Calls: `msg_info()`, `msg_ok()` message functions

**Implementation Pattern**:
```bash
customize() {
  if [[ "$PASSWORD" == "" ]]; then
    msg_info "Customizing Container"

    # Remove password requirement
    passwd -d root >/dev/null 2>&1

    # Install util-linux if needed
    apk add --no-cache --force-broken-world util-linux >/dev/null 2>&1

    # Create autologin startup script
    mkdir -p /etc/local.d
    cat > /etc/local.d/autologin.start <<'EOF'
#!/bin/sh
sed -i 's|^tty1::respawn:.*|tty1::respawn:/sbin/agetty --autologin root --noclear tty1 38400 linux|' /etc/inittab
kill -HUP 1
EOF
    chmod +x /etc/local.d/autologin.start
    touch /root/.hushlogin

    rc-update add local >/dev/null 2>&1
    /etc/local.d/autologin.start

    msg_ok "Customized Container"
  fi

  # Create update script
  echo "bash -c \"\$(curl -fsSL https://github.com/community-scripts/ProxmoxVED/raw/main/ct/${app}.sh)\"" >/usr/bin/update
  chmod +x /usr/bin/update
}
```

**Usage Examples**:

```bash
# Example 1: Passwordless auto-login
PASSWORD=""
app="myapp"
customize
# Result: Root login without password, auto-login configured
# User can type: /usr/bin/update to re-run application setup

# Example 2: Password-protected login
PASSWORD="MySecurePassword"
customize
# Result: Auto-login skipped, password remains active
# Update script still created for re-deployment
```

---

## Best Practices

### 1. **Initialization Order**

Always follow this sequence in Alpine install scripts:

```bash
#!/bin/sh
set -Eeuo pipefail

# 1. Ensure curl is available for sourcing functions
if ! command -v curl >/dev/null 2>&1; then
  apk update && apk add curl >/dev/null 2>&1
fi

# 2. Source dependencies in correct order
source <(curl -fsSL .../core.func)
source <(curl -fsSL .../error_handler.func)

# 3. Initialize function libraries
load_functions      # Sets up colors, formatting, icons
catch_errors        # Configures error traps and signal handlers

# 4. Now safe to call alpine-install.func functions
verb_ip6
setting_up_container
network_check
update_os
```

### 2. **Signal Handling**

Alpine-install.func provides comprehensive signal trap setup:

```bash
# ERR trap: Catches all command failures
trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR

# EXIT trap: Cleanup on normal or abnormal termination
trap on_exit EXIT

# INT trap: Handle Ctrl+C gracefully
trap on_interrupt INT

# TERM trap: Handle SIGTERM signal
trap on_terminate TERM
```

### 3. **Network Configuration**

Use retry logic when network may not be immediately available:

```bash
setting_up_container  # Retries up to RETRY_NUM times
network_check         # Validates DNS and Internet
```

### 4. **IPv6 Considerations**

For production Alpine containers:

```bash
# Disable IPv6 if not needed (reduces attack surface)
DISABLEIPV6="yes"
verb_ip6

# Or keep enabled (default):
DISABLEIPV6="no"
# No configuration needed
```

### 5. **Error Handling with Color Output**

Functions use color-coded message output:

```bash
msg_info   # Informational messages (yellow)
msg_ok     # Success messages (green)
msg_error  # Error messages (red)
msg_warn   # Warning messages (orange)
```

---

## Error Handling

The module implements comprehensive error handling:

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error (network unavailable, DNS failed, etc.) |
| 130 | Interrupted by user (SIGINT) |
| 143 | Terminated by signal (SIGTERM) |

### Error Handler Function

The error_handler receives three parameters:

```bash
error_handler() {
  local exit_code="$1"     # Exit code from failed command
  local line_number="$2"   # Line where error occurred
  local command="$3"       # Command that failed

  # Errors are reported with line number and command details
  # Stack trace available for debugging
}
```

### Debug Variables

Available for troubleshooting:

```bash
$VERBOSE          # Set to "yes" to show all output
$DEV_MODE_TRACE   # Set to "true" for bash -x tracing
$DEV_MODE_LOGS    # Set to "true" to persist logs
```

---

## Contributing

### Adding New Functions

When adding Alpine-specific functions:

1. Follow the established naming convention: `function_purpose()`
2. Include comprehensive docstring with signature, parameters, returns
3. Use color variables from core.func for output consistency
4. Handle errors via error_handler trap
5. Document all environment variable dependencies

### Testing New Functions

```bash
# Test function in isolation with error traps:
set -Eeuo pipefail
trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR

source <(curl -fsSL .../core.func)
source <(curl -fsSL .../error_handler.func)
load_functions
catch_errors

# Now test your function:
your_function
```

### Compatibility

- Alpine Linux 3.16+ (uses ash shell compatible syntax)
- OpenRC init system (rc-update, rc-service)
- Requires: core.func, error_handler.func
- Optional: alpine-tools.func (for extended package management)

---

## Notes

- Functions are designed for execution **inside** LXC containers (not on Proxmox host)
- Alpine uses `apk` package manager (not `apt`)
- Alpine uses OpenRC (not systemd) - use `rc-update` and `/etc/init.d/` commands
- IPv6 can be disabled for security/performance but is enabled by default
- Auto-login configuration persists across container reboots via rc-update

