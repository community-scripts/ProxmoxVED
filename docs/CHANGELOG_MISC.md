# Changelog: /misc Directory Refactoring

> **Last Updated**: November 28, 2025
> **Status**: Major Refactoring Complete

## Overview

The `/misc` directory has undergone significant refactoring to improve maintainability, security, and functionality. This document tracks all changes, removed files, and new patterns.

---

## File Status Summary

| File | Status | Notes |
|------|--------|-------|
| `api.func` | ✅ Active | API integration & reporting |
| `build.func` | ✅ Refactored | Core build orchestration (Major changes) |
| `cloud-init.sh` | ✅ Active | Cloud-Init VM configuration |
| `core.func` | ✅ Active | Core utilities & functions |
| `error_handler.func` | ✅ Active | Centralized error handling |
| `install.func` | ✅ Active | Container installation orchestration |
| `passthrough.func` | ✅ Active | Hardware passthrough utilities |
| `tools.func` | ✅ Active | Utility functions & repository setup |
| `vm-core.func` | ✅ Active | VM-specific core functions |
| `config-file.func` | ❌ **REMOVED** | Replaced by defaults system |
| `create_lxc.sh` | ❌ **REMOVED** | Replaced by install.func workflow |

---

## Major Changes in build.func

### 1. **Configuration System Overhaul**

#### ❌ Removed
- **`config-file.func` dependency**: Old configuration file format no longer used
- **Static configuration approach**: Replaced with dynamic variable-based system

#### ✅ New System: Three-Tier Defaults Architecture

```
Priority Hierarchy (Highest to Lowest):
1. Environment Variables (var_*)        ← Highest Priority
2. App-Specific Defaults (.vars files)
3. User Defaults (default.vars)
4. Built-in Defaults                    ← Fallback
```

### 2. **Variable Whitelisting System**

A new security layer has been introduced to control which variables can be persisted:

```bash
# Allowed configurable variables
VAR_WHITELIST=(
  var_apt_cacher var_apt_cacher_ip var_brg var_cpu var_disk var_fuse
  var_gateway var_hostname var_ipv6_method var_mac var_mknod var_mount_fs var_mtu
  var_net var_nesting var_ns var_protection var_pw var_ram var_tags var_timezone
  var_tun var_unprivileged var_verbose var_vlan var_ssh var_ssh_authorized_key
  var_container_storage var_template_storage
)
```

**Changes from Previous**:
- ❌ Removed: `var_ctid` (unique per container, cannot be shared)
- ❌ Removed: `var_ipv6_static` (static IPs are container-specific)

### 3. **Default Settings Management Functions**

#### `default_var_settings()`
- Creates/updates global user defaults at `/usr/local/community-scripts/default.vars`
- Loads existing defaults and merges with current settings
- Respects environment variable precedence
- Sanitizes values to prevent injection attacks

#### `get_app_defaults_path()`
- Returns app-specific defaults path: `/usr/local/community-scripts/defaults/<appname>.vars`
- Example: `/usr/local/community-scripts/defaults/pihole.vars`

#### `maybe_offer_save_app_defaults()`
- Called after advanced installation
- Offers to save current settings as app-specific defaults
- Provides diff view when updating existing defaults
- Validates against whitelist before saving

### 4. **Load Variables File Function**

#### `load_vars_file()`
- Safely loads variables from `.vars` files
- **Key Security Feature**: Does NOT use `source` or `eval`
- Manual parsing with whitelist validation
- Handles escaping and special characters
- Returns 0 on success, 1 on failure

**Example Usage**:
```bash
load_vars_file "/usr/local/community-scripts/defaults/pihole.vars"
```

### 5. **Removed Functions**

- ❌ `create_lxc()` - Replaced by install.func workflow
- ❌ `read_config()` - Replaced by load_vars_file()
- ❌ `write_config()` - Replaced by direct file generation with sanitization

---

## Installation Modes & Workflows

### Mode 1: **Default Settings**
```
Quick installation with pre-defined values
├── User selects OS/Version
├── Uses built-in defaults
└── Creates container immediately
```

**Use Case**: First-time users, basic deployments

### Mode 2: **Advanced Settings**
```
Full control over all parameters
├── User prompted for each setting
├── 19-step configuration wizard
├── Shows summary before confirmation
└── Offers to save as app defaults
```

**Use Case**: Custom configurations, experienced users

### Mode 3: **User Defaults** (formerly "My Defaults")
```
Installation using saved user defaults
├── Loads: /usr/local/community-scripts/default.vars
├── Shows loaded settings summary
└── Creates container
```

**Use Case**: Consistent deployments across multiple containers

### Mode 4: **App Defaults**
```
Installation using app-specific defaults (if available)
├── Loads: /usr/local/community-scripts/defaults/<app>.vars
├── Shows loaded settings summary
└── Creates container
```

**Use Case**: Repeat installations with saved configurations

### Mode 5: **Settings Menu**
```
Manage configuration files
├── View current settings
├── Edit storage selections
├── Manage defaults location
└── Reset to built-ins
```

**Use Case**: Configuration management

---

## Configurable Variables Reference

### Resource Allocation

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `var_cpu` | Integer | App-dependent | `4` |
| `var_ram` | Integer (MB) | App-dependent | `2048` |
| `var_disk` | Integer (GB) | App-dependent | `20` |
| `var_unprivileged` | Boolean (0/1) | `1` | `1` |

### Network Configuration

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `var_net` | String | Auto | `veth` |
| `var_brg` | String | `vmbr0` | `vmbr100` |
| `var_gateway` | IP Address | Auto-detected | `192.168.1.1` |
| `var_mtu` | Integer | `1500` | `9000` |
| `var_vlan` | Integer | None | `100` |

### Identity & Access

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `var_hostname` | String | App name | `mypihole` |
| `var_pw` | String | Random | `MySecurePass123!` |
| `var_ssh` | Boolean (yes/no) | `no` | `yes` |
| `var_ssh_authorized_key` | String | None | `ssh-rsa AAAA...` |

### Container Features

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `var_fuse` | Boolean (0/1) | `0` | `1` |
| `var_tun` | Boolean (0/1) | `0` | `1` |
| `var_nesting` | Boolean (0/1) | `0` | `1` |
| `var_keyctl` | Boolean (0/1) | `0` | `1` |
| `var_mknod` | Boolean (0/1) | `0` | `1` |
| `var_mount_fs` | String | None | `ext4` |
| `var_protection` | Boolean (0/1) | `0` | `1` |

### System Configuration

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `var_timezone` | String | System | `Europe/Berlin` |
| `var_searchdomain` | String | None | `example.com` |
| `var_apt_cacher` | String | None | `apt-cacher-ng` |
| `var_apt_cacher_ip` | IP Address | None | `192.168.1.100` |
| `var_tags` | String | App name | `docker,production` |
| `var_verbose` | Boolean (yes/no) | `no` | `yes` |

### Storage Configuration

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `var_container_storage` | String | Auto-detected | `local` |
| `var_template_storage` | String | Auto-detected | `local` |

---

## File Formats

### User Defaults: `/usr/local/community-scripts/default.vars`

```bash
# User Global Defaults
# Generated by ProxmoxVED Scripts
# Date: 2024-11-28

var_cpu=4
var_ram=2048
var_disk=20
var_unprivileged=1
var_brg=vmbr0
var_gateway=192.168.1.1
var_vlan=100
var_mtu=1500
var_hostname=mydefaults
var_timezone=Europe/Berlin
var_ssh=yes
var_ssh_authorized_key=ssh-rsa AAAAB3NzaC1...
var_container_storage=local
var_template_storage=local
```

### App Defaults: `/usr/local/community-scripts/defaults/<app>.vars`

```bash
# App-specific defaults for PiHole (pihole)
# Generated on 2024-11-28T15:32:00Z

var_unprivileged=1
var_cpu=2
var_ram=1024
var_disk=10
var_brg=vmbr0
var_net=veth
var_gateway=192.168.1.1
var_mtu=1500
var_vlan=100
var_hostname=pihole
var_timezone=Europe/Berlin
var_container_storage=local
var_template_storage=local
var_tags=dns,pihole
var_verbose=no
```

---

## Usage Examples

### Example 1: Set Global User Defaults

1. Run any app installation script
2. Select **Advanced Settings**
3. Configure all parameters
4. When prompted: **"Save as User Defaults?"** → Select **Yes**
5. File saved to: `/usr/local/community-scripts/default.vars`

**Future Installations**: Select **User Defaults** mode to reuse settings

### Example 2: Create & Use App Defaults

1. Run app installation (e.g., `pihole-install.sh`)
2. Select **Advanced Settings**
3. Fine-tune all parameters for PiHole
4. When prompted: **"Save as App Defaults for PiHole?"** → Select **Yes**
5. File saved to: `/usr/local/community-scripts/defaults/pihole.vars`

**Next Time**: 
- Run `pihole-install.sh` again
- Select **App Defaults**
- Same settings automatically applied

### Example 3: Override via Environment Variables

```bash
# Set custom values before running script
export var_cpu=8
export var_ram=4096
export var_hostname=custom-pihole

bash pihole-install.sh
```

**Priority**: Environment variables override all defaults

### Example 4: Manual File Editing

```bash
# Edit User Defaults
sudo nano /usr/local/community-scripts/default.vars

# Edit App-Specific Defaults
sudo nano /usr/local/community-scripts/defaults/pihole.vars

# Verify syntax (no source/eval, safe to read)
cat /usr/local/community-scripts/default.vars
```

---

## Security Improvements

### 1. **No `source` or `eval` Used**
- ❌ OLD: `source config_file` (Dangerous - executes arbitrary code)
- ✅ NEW: `load_vars_file()` (Safe - manual parsing with validation)

### 2. **Variable Whitelisting**
- Only explicitly allowed variables can be persisted
- Prevents accidental storage of sensitive values
- Protects against injection attacks

### 3. **Value Sanitization**
```bash
# Prevents command injection
_sanitize_value() {
  case "$1" in
  *'$('* | *'`'* | *';'* | *'&'* | *'<('*)
    return 1  # Reject dangerous values
    ;;
  esac
  echo "$1"
}
```

### 4. **File Permissions**
```bash
# Default vars accessible only to root
-rw-r--r-- root root /usr/local/community-scripts/default.vars
-rw-r--r-- root root /usr/local/community-scripts/defaults/pihole.vars
```

---

## Migration Guide

### For Users

**OLD Workflow**: Manual config file editing
**NEW Workflow**: 
1. Run installation script
2. Select "Advanced Settings"
3. Answer prompts
4. Save as defaults when offered

### For Script Developers

**OLD Pattern**:
```bash
source /path/to/config-file.conf
```

**NEW Pattern**:
```bash
# User defaults are automatically loaded in build.func
# No manual intervention needed
# Just use the variables directly
```

---

## Removed Components

### `config-file.func` (Deprecated)

**Reason**: Replaced by three-tier defaults system
- Static configuration was inflexible
- Manual editing error-prone
- No validation or sanitization

**Migration Path**: Use app/user defaults system

### `create_lxc.sh` (Deprecated)

**Reason**: Workflow integrated into install.func
- Centralized container creation logic
- Better error handling
- Unified with VM creation

**Migration Path**: Use install.func directly

---

## Future Enhancements

### Planned Features

1. **Configuration UI**: Web-based settings editor
2. **Configuration Sync**: Push defaults to multiple nodes
3. **Configuration History**: Track changes and diffs
4. **Batch Operations**: Apply defaults to multiple containers
5. **Configuration Templates**: Pre-built setting templates per app

---

## Troubleshooting

### Issue: Defaults not loading

**Solution**:
```bash
# Check if defaults file exists
ls -la /usr/local/community-scripts/default.vars

# Verify syntax
cat /usr/local/community-scripts/default.vars

# Check file permissions
sudo chown root:root /usr/local/community-scripts/default.vars
sudo chmod 644 /usr/local/community-scripts/default.vars
```

### Issue: Variable not being applied

**Solution**:
1. Check if variable is in `VAR_WHITELIST`
2. Verify variable name starts with `var_`
3. Check syntax in .vars file (no spaces around `=`)
4. Use `cat` not `source` to read files

### Issue: "Invalid option" in defaults menu

**Solution**:
- Ensure defaults directory exists: `/usr/local/community-scripts/defaults/`
- Create if missing: `sudo mkdir -p /usr/local/community-scripts/defaults/`

---

## Technical Reference

### Variable Loading Precedence

```
1. parse ARGV
2. capture ENV variables (hard environment)
3. load defaults file if exists
4. load app-specific defaults if exists
5. parse command line flags (lowest priority for overrides)

Precedence (Highest to Lowest):
  ENV var_* > AppDefaults.vars > UserDefaults.vars > Built-ins
```

### State Machine: Installation Modes

```
┌─────────────────┐
│  Start Script   │
└────────┬────────┘
         │
    ┌────v────────────────┐
    │  Display Mode Menu   │
    └────┬─────────────────┘
         │
    ┌────────────────────────────────────┐
    │  User Selects Mode                 │
    ├──────────┬──────────┬──────────┬──────────┐
    │          │          │          │          │
    v          v          v          v          v
┌─────┐ ┌────────┐ ┌──────────┐ ┌─────────┐ ┌───────┐
│Def. │ │Adv.    │ │User      │ │App      │ │Setting│
│Set. │ │Set.    │ │Default   │ │Default  │ │Menu   │
└─────┘ └────────┘ └──────────┘ └─────────┘ └───────┘
```

---

## Document Versions

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-11-28 | Initial comprehensive documentation |

---

**Last Updated**: November 28, 2025
**Maintainers**: community-scripts Team
**License**: MIT
