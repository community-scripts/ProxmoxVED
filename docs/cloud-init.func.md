# Cloud-Init.func Wiki

VM cloud-init configuration and first-boot setup module for Proxmox VEs, providing automatic system initialization, network configuration, user account setup, and SSH key management for virtual machines.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Cloud-Init Fundamentals](#cloud-init-fundamentals)
- [Main Configuration Functions](#main-configuration-functions)
- [Interactive Configuration](#interactive-configuration)
- [Configuration Parameters](#configuration-parameters)
- [Data Formats](#data-formats)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Overview

Cloud-init.func provides **VM first-boot automation** infrastructure:

- ✅ Cloud-init drive creation (IDE2 or SCSI fallback)
- ✅ User account and password configuration
- ✅ SSH public key injection
- ✅ Network configuration (DHCP or static IP)
- ✅ DNS and search domain setup
- ✅ Interactive whiptail-based configuration
- ✅ Credential file generation and display
- ✅ Support for Debian nocloud and Ubuntu cloud-init
- ✅ System package upgrade on first boot

### Integration Pattern

```bash
# In Proxmox VM creation scripts
source <(curl -fsSL .../cloud-init.func)

# Basic setup:
setup_cloud_init "$VMID" "$STORAGE" "$HOSTNAME" "yes"

# Interactive setup:
configure_cloud_init_interactive "root"
setup_cloud_init "$VMID" "$STORAGE" "$HOSTNAME" "$CLOUDINIT_ENABLE"
```

### First-Boot Sequence

```
VM Power On
    ↓
Cloud-init boot phase
    ↓
Read cloud-init config
    ↓
Create/modify user account
    ↓
Install SSH keys
    ↓
Configure network
    ↓
Set DNS/search domain
    ↓
Upgrade packages (if configured)
    ↓
Boot completion
```

---

## Cloud-Init Fundamentals

### What is Cloud-Init?

Cloud-init is a system that runs on the first boot of a VM/Instance to:
- Create user accounts
- Set passwords
- Configure networking
- Install SSH keys
- Run custom scripts
- Manage system configuration

### Proxmox Cloud-Init Integration

Proxmox VE supports cloud-init natively via:
- **Cloud-init drive**: IDE2 or SCSI disk with cloud-init data
- **QEMU parameters**: User, password, SSH keys, IP configuration
- **First-boot services**: systemd services that execute on first boot

### Nocloud Data Source

Proxmox uses the **nocloud** data source (no internet required):
- Configuration stored on local cloud-init drive
- No external network call needed
- Works in isolated networks
- Suitable for private infrastructure

---

## Main Configuration Functions

### `setup_cloud_init()`

**Purpose**: Configures Cloud-init for automatic VM first-boot setup.

**Signature**:
```bash
setup_cloud_init()
```

**Parameters**:
- `$1` - VMID (required, e.g., 100)
- `$2` - Storage name (required, e.g., local, local-lvm)
- `$3` - Hostname (optional, default: vm-${VMID})
- `$4` - Enable Cloud-Init (yes/no, default: no)
- `$5` - User (optional, default: root)
- `$6` - Network mode (dhcp/static, default: dhcp)
- `$7` - Static IP (optional, CIDR format: 192.168.1.100/24)
- `$8` - Gateway (optional)
- `$9` - Nameservers (optional, space-separated, default: 1.1.1.1 8.8.8.8)

**Returns**: 0 on success, 1 on failure; exits if not enabled

**Behavior**:
```bash
# If enable="no":
# Returns immediately (skips all configuration)

# If enable="yes":
# 1. Create cloud-init drive (IDE2, fallback to SCSI1)
# 2. Set user account
# 3. Generate random password
# 4. Configure network
# 5. Set DNS servers
# 6. Add SSH keys (if available)
# 7. Save credentials to file
# 8. Export variables for calling script
```

**Operations**:

| Operation | Command | Purpose |
|-----------|---------|---------|
| Create drive | `qm set $vmid --ide2 $storage:cloudinit` | Cloud-init data disk |
| Set user | `qm set $vmid --ciuser $ciuser` | Initial user |
| Set password | `qm set $vmid --cipassword $cipassword` | Auto-generated |
| SSH keys | `qm set $vmid --sshkeys $SSH_KEYS_FILE` | Pre-injected |
| DHCP network | `qm set $vmid --ipconfig0 ip=dhcp` | Dynamic IP |
| Static network | `qm set $vmid --ipconfig0 ip=192.168.1.100/24,gw=192.168.1.1` | Fixed IP |
| DNS | `qm set $vmid --nameserver $servers` | 1.1.1.1 8.8.8.8 |
| Search domain | `qm set $vmid --searchdomain local` | Local domain |

**Environment Variables Set**:
- `CLOUDINIT_USER` - Username configured
- `CLOUDINIT_PASSWORD` - Generated password (in memory only)
- `CLOUDINIT_CRED_FILE` - Path to credentials file

**Usage Examples**:

```bash
# Example 1: Basic DHCP setup
VMID=100
STORAGE="local-lvm"
setup_cloud_init "$VMID" "$STORAGE" "myvm" "yes"
# Result: VM configured with DHCP, random password, root user

# Example 2: Static IP configuration
setup_cloud_init "$VMID" "$STORAGE" "myvm" "yes" "root" \
  "static" "192.168.1.100/24" "192.168.1.1" "1.1.1.1 8.8.8.8"
# Result: VM configured with static IP, specific DNS

# Example 3: Disabled (no cloud-init)
setup_cloud_init "$VMID" "$STORAGE" "myvm" "no"
# Result: Function returns immediately, no configuration
```

---

### `configure_cloud_init_interactive()`

**Purpose**: Interactive whiptail-based configuration prompts for user preferences.

**Signature**:
```bash
configure_cloud_init_interactive()
```

**Parameters**:
- `$1` - Default user (optional, default: root)

**Returns**: 0 on success, 1 if whiptail unavailable; exports configuration variables

**Environment Variables Exported**:
- `CLOUDINIT_ENABLE` - Enable (yes/no)
- `CLOUDINIT_USER` - Username
- `CLOUDINIT_NETWORK_MODE` - dhcp or static
- `CLOUDINIT_IP` - Static IP (if static mode)
- `CLOUDINIT_GW` - Gateway (if static mode)
- `CLOUDINIT_DNS` - DNS servers (space-separated)

**User Prompts** (5 questions):
1. **Enable Cloud-Init?** (yes/no)
2. **Username?** (default: root)
3. **Network Mode?** (DHCP or static)
4. **Static IP?** (if static, CIDR format)
5. **Gateway IP?** (if static)
6. **DNS Servers?** (default: 1.1.1.1 8.8.8.8)

**Fallback Behavior**:
- If whiptail unavailable: Shows warning and returns 1
- Auto-defaults to DHCP if error occurs
- Non-interactive: Can be skipped in scripts

**Implementation Pattern**:
```bash
configure_cloud_init_interactive() {
  local default_user="${1:-root}"

  # Check whiptail availability
  if ! command -v whiptail >/dev/null 2>&1; then
    echo "Warning: whiptail not available"
    export CLOUDINIT_ENABLE="no"
    return 1
  fi

  # Ask enable
  if ! (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLOUD-INIT" \
    --yesno "Enable Cloud-Init for VM configuration?" 16 68); then
    export CLOUDINIT_ENABLE="no"
    return 0
  fi

  export CLOUDINIT_ENABLE="yes"

  # Username
  CLOUDINIT_USER=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox \
    "Cloud-Init Username" 8 58 "$default_user" --title "USERNAME" 3>&1 1>&2 2>&3)
  export CLOUDINIT_USER="${CLOUDINIT_USER:-$default_user}"

  # Network mode
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "NETWORK MODE" \
    --yesno "Use DHCP for network configuration?" 10 58); then
    export CLOUDINIT_NETWORK_MODE="dhcp"
  else
    export CLOUDINIT_NETWORK_MODE="static"
    # ... prompt for static IP and gateway ...
  fi

  # DNS servers
  CLOUDINIT_DNS=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox \
    "DNS Servers (space-separated)" 8 58 "1.1.1.1 8.8.8.8" --title "DNS" 3>&1 1>&2 2>&3)
  export CLOUDINIT_DNS
}
```

**Usage Examples**:

```bash
# Example 1: Interactive configuration
configure_cloud_init_interactive "root"
# Prompts user for all settings interactively
# Exports variables for use in setup_cloud_init()

# Example 2: With custom default user
configure_cloud_init_interactive "debian"
# Suggests "debian" as default username

# Example 3: In script workflow
configure_cloud_init_interactive "$DEFAULT_USER"
setup_cloud_init "$VMID" "$STORAGE" "$HOSTNAME" "$CLOUDINIT_ENABLE" "$CLOUDINIT_USER"
# User configures interactively, then script sets up VM
```

---

## Configuration Parameters

### VMID (Virtual Machine ID)

- **Type**: Integer (100-2147483647)
- **Required**: Yes
- **Example**: `100`
- **Validation**: Must be unique, >= 100 on Proxmox

### Storage

- **Type**: String (storage backend name)
- **Required**: Yes
- **Examples**: `local`, `local-lvm`, `ceph-rbd`
- **Validation**: Must exist in Proxmox
- **Cloud-init Drive**: Placed on this storage

### Hostname

- **Type**: String (valid hostname)
- **Required**: No (defaults to vm-${VMID})
- **Example**: `myvm`, `web-server-01`
- **Format**: Lowercase, alphanumeric, hyphens allowed

### User

- **Type**: String (username)
- **Required**: No (defaults: root)
- **Example**: `root`, `ubuntu`, `debian`
- **Cloud-init**: User account created on first boot

### Network Mode

- **Type**: Enum (dhcp, static)
- **Default**: dhcp
- **Options**:
  - `dhcp` - Dynamic IP from DHCP server
  - `static` - Manual IP configuration

### Static IP

- **Format**: CIDR notation (192.168.1.100/24)
- **Example**: `192.168.1.50/24`, `10.0.0.5/8`
- **Validation**: Valid IP and netmask
- **Required**: If network mode = static

### Gateway

- **Format**: IP address (192.168.1.1)
- **Example**: `192.168.1.1`, `10.0.0.1`
- **Validation**: Valid IP
- **Required**: If network mode = static

### Nameservers

- **Format**: Space-separated IPs
- **Default**: `1.1.1.1 8.8.8.8`
- **Example**: `1.1.1.1 8.8.8.8 9.9.9.9`

### DNS Search Domain

- **Type**: String
- **Default**: `local`
- **Example**: `example.com`, `internal.corp`

---

## Data Formats

### Cloud-Init Credentials File

Generated at: `/tmp/${hostname}-${vmid}-cloud-init-credentials.txt`

**Format**:
```
========================================
Cloud-Init Credentials
========================================
VM ID:    100
Hostname: myvm
Created:  Tue Dec 01 10:30:00 UTC 2024

Username: root
Password: s7k9mL2pQ8wX

Network:  dhcp
DNS:      1.1.1.1 8.8.8.8

========================================
SSH Access (if keys configured):
ssh root@<vm-ip>

Proxmox UI Configuration:
VM 100 > Cloud-Init > Edit
- User, Password, SSH Keys
- Network (IP Config)
- DNS, Search Domain
========================================
```

### Proxmox Cloud-Init Config

Stored in: `/etc/pve/nodes/<node>/qemu-server/<vmid>.conf`

**Relevant Settings**:
```
ide2: local-lvm:vm-100-cloudinit,media=cdrom
ciuser: root
cipassword: (encrypted)
ipconfig0: ip=dhcp
nameserver: 1.1.1.1 8.8.8.8
searchdomain: local
```

### Network Configuration Examples

**DHCP**:
```bash
qm set 100 --ipconfig0 "ip=dhcp"
```

**Static IPv4**:
```bash
qm set 100 --ipconfig0 "ip=192.168.1.100/24,gw=192.168.1.1"
```

**Static IPv6**:
```bash
qm set 100 --ipconfig0 "ip6=2001:db8::100/64,gw6=2001:db8::1"
```

**Dual Stack (IPv4 + IPv6)**:
```bash
qm set 100 --ipconfig0 "ip=192.168.1.100/24,gw=192.168.1.1,ip6=2001:db8::100/64,gw6=2001:db8::1"
```

---

## Best Practices

### 1. **Always Configure SSH Keys**

```bash
# Ensure SSH keys available before cloud-init setup
CLOUDINIT_SSH_KEYS="/root/.ssh/authorized_keys"

if [ ! -f "$CLOUDINIT_SSH_KEYS" ]; then
  mkdir -p /root/.ssh
  # Generate or import SSH keys
fi

setup_cloud_init "$VMID" "$STORAGE" "$HOSTNAME" "yes"
```

### 2. **Save Credentials Securely**

```bash
# After setup_cloud_init():
# Credentials file generated at $CLOUDINIT_CRED_FILE

# Copy to secure location:
cp "$CLOUDINIT_CRED_FILE" "/root/vm-credentials/"
chmod 600 "/root/vm-credentials/$(basename $CLOUDINIT_CRED_FILE)"

# Or display to user:
cat "$CLOUDINIT_CRED_FILE"
```

### 3. **Use Static IPs for Production**

```bash
# DHCP - suitable for dev/test
setup_cloud_init "$VMID" "$STORAGE" "$HOSTNAME" "yes" "root" "dhcp"

# Static - suitable for production
setup_cloud_init "$VMID" "$STORAGE" "$HOSTNAME" "yes" "root" \
  "static" "192.168.1.100/24" "192.168.1.1"
```

### 4. **Validate Network Configuration**

```bash
# Before setting up cloud-init, ensure:
# - Gateway IP is reachable
# - IP address not in use
# - DNS servers are accessible

ping -c 1 "$GATEWAY" || msg_error "Gateway unreachable"
```

### 5. **Test First Boot**

```bash
# After cloud-init setup:
qm start "$VMID"

# Wait for boot
sleep 10

# Check cloud-init status
qm exec "$VMID" cloud-init status

# Verify network configuration
qm exec "$VMID" hostname -I
```

---

## Troubleshooting

### Cloud-Init Not Applying

```bash
# Inside VM:
cloud-init status        # Show cloud-init status
cloud-init analyze       # Analyze cloud-init boot
cloud-init query         # Query cloud-init datasource

# Check logs:
tail -100 /var/log/cloud-init-output.log
tail -100 /var/log/cloud-init.log
```

### Network Not Configured

```bash
# Verify cloud-init config in Proxmox:
cat /etc/pve/nodes/$(hostname)/qemu-server/100.conf

# Check cloud-init drive:
qm config 100 | grep ide2

# In VM, verify cloud-init wrote config:
cat /etc/netplan/99-cloudinit.yaml
```

### SSH Keys Not Installed

```bash
# Verify SSH keys set in Proxmox:
qm config 100 | grep sshkeys

# In VM, check SSH directory:
ls -la /root/.ssh/
cat /root/.ssh/authorized_keys
```

### Password Not Set

```bash
# Regenerate cloud-init drive:
qm set 100 --delete ide2        # Remove cloud-init drive
qm set 100 --ide2 local-lvm:vm-100-cloudinit,media=cdrom  # Re-create

# Set password again:
qm set 100 --cipassword "newpassword"
```

---

## Contributing

### Adding New Configuration Options

1. Add parameter to `setup_cloud_init()` function signature
2. Add validation for parameter
3. Add `qm set` command to apply configuration
4. Update documentation with examples
5. Test on actual Proxmox VE

### Enhancing Interactive Configuration

1. Add new whiptail dialog to `configure_cloud_init_interactive()`
2. Export variable for use in setup
3. Add validation logic
4. Test with various input scenarios

### Supporting New Data Sources

Beyond nocloud, could support:
- ConfigDrive (cloud-init standard)
- ESXi (if supporting vSphere)
- Hyper-V (if supporting Windows)

---

## Notes

- Cloud-init requires **QEMU guest agent** for optimal functionality
- Network configuration applied **on first boot only**
- Credentials file contains **sensitive information** - keep secure
- SSH keys are **persisted** and not displayed in credentials file
- Cloud-init is **optional** - VMs work without it

