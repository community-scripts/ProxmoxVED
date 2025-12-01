# Build.func Wiki

Central LXC container build and configuration orchestration engine providing the main creation workflow, 19-step advanced wizard, defaults system, variable management, and state machine for container lifecycle.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Core Functions](#core-functions)
- [Variable Management](#variable-management)
- [Build Workflow](#build-workflow)
- [Advanced Settings Wizard](#advanced-settings-wizard)
- [Defaults System](#defaults-system)
- [Best Practices](#best-practices)
- [Development Mode](#development-mode)
- [Contributing](#contributing)

---

## Overview

Build.func is the **3800+ line orchestration engine** for LXC container creation:

- ✅ 19-step interactive advanced settings wizard
- ✅ 3-tier defaults precedence system (app → user → global)
- ✅ Variable whitelisting for security
- ✅ State machine workflow management
- ✅ Container resource allocation (CPU, RAM, disk)
- ✅ Storage selection and validation
- ✅ Network configuration (bridge, MAC, VLAN, IPv6)
- ✅ Session tracking and logging
- ✅ Comprehensive pre-flight validation checks

### Execution Flow

```
Script Invocation
     ↓
variables()  → Initialize core variables, SESSION_ID, UUID
     ↓
build.func functions sourced
     ↓
Pre-flight checks (maxkeys, template availability)
     ↓
Create container (pct create ...)
     ↓
Network configuration
     ↓
Storage tuning
     ↓
Installation script execution
     ↓
Completion & cleanup
```

---

## Core Functions

### `variables()`

**Purpose**: Initializes all core variables, generates unique session ID, and captures application defaults for precedence logic.

**Signature**:
```bash
variables()
```

**Parameters**: None

**Returns**: No explicit return value (sets global variables)

**Variables Initialized**:

| Variable | Source | Purpose |
|----------|--------|---------|
| `NSAPP` | `APP` converted to lowercase | Normalized app name |
| `var_install` | `${NSAPP}-install` | Installation script name |
| `PVEHOST_NAME` | `hostname` | Proxmox hostname |
| `DIAGNOSTICS` | Set to "yes" | Enable telemetry |
| `METHOD` | Set to "default" | Setup method |
| `RANDOM_UUID` | `/proc/sys/kernel/random/uuid` | Session UUID |
| `SESSION_ID` | First 8 chars of UUID | Short session ID |
| `BUILD_LOG` | `/tmp/create-lxc-${SESSION_ID}.log` | Host-side log file |
| `PVEVERSION` | `pveversion` | Proxmox VE version |
| `KERNEL_VERSION` | `uname -r` | System kernel version |

**App Default Capture** (3-tier precedence):
```bash
# Tier 1: App-declared defaults (highest priority)
APP_DEFAULT_CPU=${var_cpu:-}
APP_DEFAULT_RAM=${var_ram:-}
APP_DEFAULT_DISK=${var_disk:-}

# Tier 2: User configuration (~/.community-scripts/defaults)
# Tier 3: Global defaults (built-in)
```

**Dev Mode Setup**:
```bash
# Parse dev_mode early for special behaviors
parse_dev_mode

# If dev_mode=logs, use persistent logging location
if [[ "${DEV_MODE_LOGS}" == "true" ]]; then
  mkdir -p /var/log/community-scripts
  BUILD_LOG="/var/log/community-scripts/create-lxc-${SESSION_ID}-$(date +%Y%m%d_%H%M%S).log"
fi
```

**Usage Examples**:

```bash
# Example 1: Initialize with default app
APP="Jellyfin"
variables
# Result:
# NSAPP="jellyfin"
# SESSION_ID="550e8400"
# BUILD_LOG="/tmp/create-lxc-550e8400.log"

# Example 2: With dev mode
dev_mode="trace,logs"
APP="MyApp"
variables
# Result:
# Persistent logging enabled
# Bash tracing configured
# BUILD_LOG="/var/log/community-scripts/create-lxc-550e8400-20241201_103000.log"
```

---

### `maxkeys_check()`

**Purpose**: Validates kernel keyring limits don't prevent container creation (prevents "key quota exceeded" errors).

**Signature**:
```bash
maxkeys_check()
```

**Parameters**: None

**Returns**: 0 if limits acceptable; exits with error if exceeded

**Checks**:
- `/proc/sys/kernel/keys/maxkeys` - Maximum keys per user
- `/proc/sys/kernel/keys/maxbytes` - Maximum key bytes per user
- `/proc/key-users` - Current usage for UID 100000 (LXC user)

**Warning Thresholds**:
- Keys: Current >= (maxkeys - 100)
- Bytes: Current >= (maxbytes - 1000)

**Recovery Suggestions**:
```bash
# If warning triggered, suggests sysctl configuration
sysctl -w kernel.keys.maxkeys=200000
sysctl -w kernel.keys.maxbytes=40000000

# Add to persistent config
echo "kernel.keys.maxkeys=200000" >> /etc/sysctl.d/98-community-scripts.conf
sysctl -p
```

**Usage Examples**:

```bash
# Example 1: Healthy keyring usage
maxkeys_check
# Silent success: Usage is normal

# Example 2: Near limit
maxkeys_check
# Warning displayed with suggested sysctl values
# Allows continuation but recommends tuning

# Example 3: Exceeded limit
maxkeys_check
# Error: Exits with code 1
# Suggests increasing limits before retry
```

---

## Variable Management

### `default_var_settings()`

**Purpose**: Loads or creates default variable settings with 3-tier precedence.

**Signature**:
```bash
default_var_settings()
```

**Precedence Order**:
```
1. App-declared defaults (var_cpu, var_ram, var_disk from script)
2. User defaults (~/.community-scripts/defaults.sh)
3. Global built-in defaults
```

**User Defaults Location**:
```bash
~/.community-scripts/defaults.sh
```

**Example User Defaults File**:
```bash
# ~/.community-scripts/defaults.sh
CORE_COUNT=4            # Override default CPU
RAM_SIZE=4096           # Override default RAM (MB)
DISK_SIZE=32            # Override default disk (GB)
BRIDGE="vmbr0"          # Preferred bridge
STORAGE="local-lvm"     # Preferred storage
DISABLEIPV6="no"        # Network preference
VERBOSE="no"            # Output preference
```

---

### `load_vars_file()`

**Purpose**: Loads saved container variables from previous configuration.

**Signature**:
```bash
load_vars_file()
```

**Parameters**: None

**Returns**: 0 if loaded; 1 if no saved config found

**File Location**:
```bash
~/.community-scripts/${NSAPP}.vars
```

**Variables Loaded**:
- All whitelist-approved variables (CORE_COUNT, RAM_SIZE, DISK_SIZE, etc.)
- Saved settings from previous container creation

**Usage Examples**:

```bash
# Example 1: Load previous config
if load_vars_file; then
  msg_ok "Loaded previous settings for $NSAPP"
else
  msg_info "No previous configuration found, using defaults"
fi

# Example 2: Offer to use saved config
# Interactive: Prompts user to confirm previously saved values
```

---

### `maybe_offer_save_app_defaults()`

**Purpose**: Optionally saves current configuration for reuse in future container creations.

**Signature**:
```bash
maybe_offer_save_app_defaults()
```

**Parameters**: None

**Returns**: No explicit return value (saves or skips)

**Behavior**:
- Prompts user if they want to save current settings
- Saves to `~/.community-scripts/${NSAPP}.vars`
- User can load these settings in future runs via `load_vars_file()`
- Saves whitelisted variables only (security)

**Variables Saved**:
- CORE_COUNT, RAM_SIZE, DISK_SIZE
- BRIDGE, STORAGE, MACADDRESS
- VLAN_TAG, DISABLEIPV6
- PASSWORD settings
- Custom network configuration

**Usage Examples**:

```bash
# Example 1: After configuration
configure_container
# ... all settings done ...
maybe_offer_save_app_defaults
# Prompts: "Save these settings for future use? [y/n]"
# If yes: Saves to ~/.community-scripts/jellyfin.vars

# Example 2: Reload in next run
# User runs script again
# Prompted: "Use saved settings from last time? [y/n]"
# If yes: Load_vars_file() populates all variables
```

---

## Build Workflow

### `install_script()`

**Purpose**: Orchestrates container installation workflow inside the LXC container.

**Signature**:
```bash
install_script()
```

**Parameters**: None (uses global `NSAPP` variable)

**Returns**: 0 on success; exits with error code on failure

**Installation Steps**:
1. Copy install script into container
2. Execute via `pct exec $CTID bash /tmp/...`
3. Capture output and exit code
4. Report completion to API
5. Handle errors with cleanup

**Error Handling**:
```bash
# If installation fails:
# - Captures exit code
# - Posts failure to API (if telemetry enabled)
# - Displays error with explanation
# - Offers debug shell (if DEV_MODE_BREAKPOINT)
# - Cleans up container (unless DEV_MODE_KEEP)
```

---

## Advanced Settings Wizard

### `advanced_settings()`

**Purpose**: Interactive 19-step wizard for advanced container configuration.

**Signature**:
```bash
advanced_settings()
```

**Parameters**: None

**Returns**: No explicit return value (populates variables)

**Wizard Steps** (19 total):
1. **CPU Cores** - Allocation (1-128)
2. **RAM Size** - Allocation in MB (256-65536)
3. **Disk Size** - Allocation in GB (1-4096)
4. **Storage** - Select storage backend (local, local-lvm, etc.)
5. **Bridge** - Network bridge (vmbr0, vmbr1, etc.)
6. **MAC Address** - Custom or auto-generated
7. **VLAN Tag** - Optional VLAN configuration
8. **IPv6** - Enable/disable IPv6
9. **Disable IPV6** - Explicit disable option
10. **DHCP** - DHCP or static IP
11. **IP Configuration** - If static: IP/mask
12. **Gateway** - Network gateway
13. **DNS** - DNS server configuration
14. **Hostname** - Container hostname
15. **Root Password** - Set or leave empty (auto-login)
16. **SSH Access** - Enable root SSH
17. **Features** - FUSE, Nesting, keyctl, etc.
18. **Start on Boot** - Autostart configuration
19. **Privileged Mode** - Privileged or unprivileged container

**User Input Methods**:
- Whiptail dialogs (graphical)
- Command-line prompts (fallback)
- Validation of all inputs
- Confirmation summary before creation

**Usage Examples**:

```bash
# Example 1: Run wizard
advanced_settings
# User prompted for each of 19 settings
# Responses stored in variables

# Example 2: Scripted (skip prompts)
CORE_COUNT=4
RAM_SIZE=4096
DISK_SIZE=32
# ... set all 19 variables ...
# advanced_settings() skips prompts since variables already set
```

---

## Defaults System

### 3-Tier Precedence Logic

**Tier 1 (Highest Priority): App-Declared Defaults**
```bash
# In app script header (before default.vars sourced):
var_cpu=4
var_ram=2048
var_disk=20

# If user has higher value in tier 2/3, app value takes precedence
```

**Tier 2 (Medium Priority): User Defaults**
```bash
# In ~/.community-scripts/defaults.sh:
CORE_COUNT=6
RAM_SIZE=4096
DISK_SIZE=32

# Can be overridden by app defaults (tier 1)
```

**Tier 3 (Lowest Priority): Global Built-in Defaults**
```bash
# Built into build.func:
CORE_COUNT=2 (default)
RAM_SIZE=2048 (default, in MB)
DISK_SIZE=8 (default, in GB)
```

**Resolution Algorithm**:
```bash
# For CPU cores (example):
if [ -n "$APP_DEFAULT_CPU" ]; then
  CORE_COUNT=$APP_DEFAULT_CPU    # Tier 1 wins
elif [ -n "$USER_DEFAULT_CPU" ]; then
  CORE_COUNT=$USER_DEFAULT_CPU   # Tier 2
else
  CORE_COUNT=2                   # Tier 3 (global)
fi
```

---

## Best Practices

### 1. **Always Call variables() First**

```bash
#!/bin/bash
source <(curl -fsSL .../build.func)
load_functions
catch_errors

# Must be first real function call
variables

# Then safe to use SESSION_ID, BUILD_LOG, etc.
msg_info "Building container (Session: $SESSION_ID)"
```

### 2. **Declare App Defaults Before Sourcing build.func**

```bash
#!/bin/bash
# Declare app defaults BEFORE sourcing build.func
var_cpu=4
var_ram=4096
var_disk=20

source <(curl -fsSL .../build.func)
variables  # These defaults are captured

# Now var_cpu, var_ram, var_disk are in APP_DEFAULT_*
```

### 3. **Use Variable Whitelisting**

```bash
# Only these variables are allowed to be saved/loaded:
WHITELIST="CORE_COUNT RAM_SIZE DISK_SIZE BRIDGE STORAGE MACADDRESS VLAN_TAG DISABLEIPV6"

# Sensitive variables are NEVER saved:
# PASSWORD, SSH keys, API tokens, etc.
```

### 4. **Check Pre-flight Conditions**

```bash
variables
maxkeys_check          # Validate kernel limits
pve_check              # Validate PVE version
arch_check             # Validate architecture

# Only proceed after all checks pass
msg_ok "Pre-flight checks passed"
```

### 5. **Track Sessions**

```bash
# Use SESSION_ID in all logs
BUILD_LOG="/tmp/create-lxc-${SESSION_ID}.log"

# Keep logs for troubleshooting
# Can be reviewed later: tail -50 /tmp/create-lxc-550e8400.log
```

---

## Development Mode

### Dev Mode Variables

Set via environment or in script:

```bash
dev_mode="trace,keep,breakpoint"
parse_dev_mode

# Enables:
# - DEV_MODE_TRACE=true (bash -x)
# - DEV_MODE_KEEP=true (never delete container)
# - DEV_MODE_BREAKPOINT=true (shell on error)
```

### Debug Container Creation

```bash
# Run with all debugging enabled
dev_mode="trace,keep,logs" bash ct/jellyfin.sh

# Then review logs:
tail -200 /var/log/community-scripts/create-lxc-*.log

# Container stays running (DEV_MODE_KEEP)
# Allows ssh inspection: ssh root@<container-ip>
```

---

## Contributing

### Adding New Wizard Steps

1. Add step number and variable to documentation
2. Add whiptail prompt in `advanced_settings()`
3. Add validation logic
4. Add to whitelist if user should save it
5. Update documentation with examples

### Extending Defaults System

To add new tier or change precedence:

1. Update 3-tier logic section
2. Modify resolution algorithm
3. Document new precedence order
4. Update whitelist accordingly

### Testing Build Workflow

```bash
# Test with dry-run mode
dev_mode="dryrun" bash ct/myapp.sh
# Shows all commands without executing

# Test with keep mode
dev_mode="keep" bash ct/myapp.sh
# Container stays if fails, allows inspection
```

---

## Notes

- Build.func is **large and complex** (3800+ lines) - handles most container creation logic
- Variables are **passed to container** via pct set/environment
- Session ID **enables request tracking** across distributed logs
- Defaults system is **flexible** (3-tier precedence)
- Pre-flight checks **prevent many common errors**

