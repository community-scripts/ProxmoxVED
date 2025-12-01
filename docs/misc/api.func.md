# API.func Wiki

A telemetry and diagnostics module providing anonymous statistics collection and API integration with the Community-Scripts infrastructure for tracking container/VM creation metrics and installation success/failure data.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Exit Code Reference](#exit-code-reference)
- [Telemetry Functions](#telemetry-functions)
- [API Payload Structure](#api-payload-structure)
- [Privacy & Opt-Out](#privacy--opt-out)
- [Error Mapping](#error-mapping)
- [Best Practices](#best-practices)
- [API Integration](#api-integration)
- [Contributing](#contributing)

---

## Overview

The API.func module provides anonymous telemetry reporting to Community-Scripts infrastructure, enabling:

- ✅ Container/VM creation statistics collection
- ✅ Installation success/failure tracking
- ✅ Comprehensive exit code mapping and explanation
- ✅ Anonymous session-based tracking (UUID)
- ✅ Privacy-respecting data collection (no personal data)
- ✅ Opt-out capability via DIAGNOSTICS setting
- ✅ Consistent error reporting across all scripts

### Integration Points

```bash
# In container build scripts (on Proxmox host):
source <(curl -fsSL .../api.func)
post_to_api          # Report container creation
post_update_to_api   # Report installation completion

# Error handling (in all scripts):
source <(curl -fsSL .../error_handler.func)
# explain_exit_code shared for consistent mappings
```

### Data Flow

```
Container/VM Creation
         ↓
    post_to_api()
         ↓
Community-Scripts API
         ↓
Anonymous Statistics
(No personal data)
```

---

## Exit Code Reference

### Category 1: Generic / Shell Errors

| Code | Meaning | Recovery |
|------|---------|----------|
| 1 | General error / Operation not permitted | Check permissions, re-run command |
| 2 | Misuse of shell builtins (syntax error) | Fix shell syntax, validate script |
| 126 | Command invoked cannot execute | Fix file permissions (chmod +x) |
| 127 | Command not found | Install missing package or tool |
| 128 | Invalid argument to exit | Check exit code parameter (0-255) |
| 130 | Terminated by Ctrl+C (SIGINT) | User interrupted - retry manually |
| 137 | Killed (SIGKILL / Out of memory) | Insufficient RAM - increase allocation |
| 139 | Segmentation fault (core dumped) | Serious application bug - contact support |
| 143 | Terminated (SIGTERM) | System shutdown or manual termination |

### Category 2: Package Manager Errors

| Code | Meaning | Recovery |
|------|---------|----------|
| 100 | APT: Package manager error (broken packages) | Run `apt --fix-broken install` |
| 101 | APT: Configuration error (bad sources.list) | Fix /etc/apt/sources.list, re-run apt update |
| 255 | DPKG: Fatal internal error | Run `dpkg --configure -a` |

### Category 3: Node.js / npm Errors

| Code | Meaning | Recovery |
|------|---------|----------|
| 243 | Node.js: Out of memory (heap out of memory) | Increase container RAM, reduce workload |
| 245 | Node.js: Invalid command-line option | Check node/npm arguments |
| 246 | Node.js: Internal JavaScript Parse Error | Update Node.js version |
| 247 | Node.js: Fatal internal error | Check Node.js installation integrity |
| 248 | Node.js: Invalid C++ addon / N-API failure | Rebuild native modules |
| 249 | Node.js: Inspector error | Disable debugger, retry |
| 254 | npm/pnpm/yarn: Unknown fatal error | Check package.json, clear cache |

### Category 4: Python Errors

| Code | Meaning | Recovery |
|------|---------|----------|
| 210 | Python: Virtualenv / uv environment missing | Recreate virtual environment |
| 211 | Python: Dependency resolution failed | Check package versions, fix conflicts |
| 212 | Python: Installation aborted (EXTERNALLY-MANAGED) | Use venv or remove marker file |

### Category 5: Database Errors

#### PostgreSQL

| Code | Meaning | Recovery |
|------|---------|----------|
| 231 | Connection failed (server not running) | Start PostgreSQL service |
| 232 | Authentication failed (bad user/password) | Verify credentials |
| 233 | Database does not exist | Create database: `createdb dbname` |
| 234 | Fatal error in query / syntax error | Fix SQL syntax |

#### MySQL / MariaDB

| Code | Meaning | Recovery |
|------|---------|----------|
| 241 | Connection failed (server not running) | Start MySQL/MariaDB service |
| 242 | Authentication failed (bad user/password) | Reset password, verify credentials |
| 243 | Database does not exist | Create database: `CREATE DATABASE dbname;` |
| 244 | Fatal error in query / syntax error | Fix SQL syntax |

#### MongoDB

| Code | Meaning | Recovery |
|------|---------|----------|
| 251 | Connection failed (server not running) | Start MongoDB daemon |
| 252 | Authentication failed (bad user/password) | Verify credentials, reset if needed |
| 253 | Database not found | Create database in MongoDB shell |
| 254 | Fatal query error | Check query syntax |

### Category 6: Proxmox Custom Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| 200 | Failed to create lock file | Check /tmp permissions |
| 203 | Missing CTID variable | CTID must be provided to script |
| 204 | Missing PCT_OSTYPE variable | OS type not detected |
| 205 | Invalid CTID (<100) | Container ID must be >= 100 |
| 206 | CTID already in use | Check `pct list`, remove conflicting container |
| 207 | Password contains special characters | Use alphanumeric only for passwords |
| 208 | Invalid configuration format | Check DNS/MAC/Network format |
| 209 | Container creation failed | Check pct create output for details |
| 210 | Cluster not quorate | Ensure cluster nodes are online |
| 211 | Timeout waiting for template lock | Wait for concurrent downloads to finish |
| 214 | Not enough storage space | Free up disk space or expand storage |
| 215 | Container created but not listed | Check /etc/pve/lxc/ for config files |
| 216 | RootFS entry missing in config | Incomplete container creation |
| 217 | Storage does not support rootdir | Use compatible storage backend |
| 218 | Template corrupted or incomplete | Re-download template |
| 220 | Unable to resolve template path | Verify template availability |
| 221 | Template not readable | Fix file permissions |
| 222 | Template download failed (3 attempts) | Check network/storage |
| 223 | Template not available after download | Storage sync issue |
| 225 | No template for OS/Version | Run `pveam available` to see options |
| 231 | LXC stack upgrade/retry failed | Update pve-container package |

---

## Telemetry Functions

### `explain_exit_code()`

**Purpose**: Maps numeric exit codes to human-readable error descriptions. Shared between api.func and error_handler.func for consistency.

**Signature**:
```bash
explain_exit_code()
```

**Parameters**:
- `$1` - Numeric exit code (0-255)

**Returns**: Human-readable description string

**Supported Codes**:
- 1-2, 126-128, 130, 137, 139, 143 (Shell)
- 100-101, 255 (Package managers)
- 210-212 (Python)
- 231-234 (PostgreSQL)
- 241-244 (MySQL/MariaDB)
- 243-249, 254 (Node.js/npm)
- 251-254 (MongoDB)
- 200-231 (Proxmox custom)

**Default**: Returns "Unknown error" for unmapped codes

**Usage Examples**:

```bash
# Example 1: Common error
explain_exit_code 127
# Output: "Command not found"

# Example 2: Database error
explain_exit_code 241
# Output: "MySQL/MariaDB: Connection failed (server not running / wrong socket)"

# Example 3: Custom Proxmox error
explain_exit_code 206
# Output: "Custom: CTID already in use (check 'pct list' and /etc/pve/lxc/)"

# Example 4: Unknown code
explain_exit_code 999
# Output: "Unknown error"
```

---

### `post_to_api()`

**Purpose**: Sends LXC container creation statistics to Community-Scripts telemetry API.

**Signature**:
```bash
post_to_api()
```

**Parameters**: None (uses global environment variables)

**Returns**: No explicit return value (curl result stored in RESPONSE if diagnostics enabled)

**Requirements** (Silent fail if not met):
- `curl` command available
- `DIAGNOSTICS="yes"`
- `RANDOM_UUID` is set
- Executed on Proxmox host (has access to `pveversion`)

**Environment Variables Used**:
- `CT_TYPE` - Container type (privileged=1, unprivileged=0)
- `DISK_SIZE` - Allocated disk in GB
- `CORE_COUNT` - CPU core count
- `RAM_SIZE` - RAM allocated in MB
- `var_os` - Operating system name
- `var_version` - OS version
- `NSAPP` - Normalized application name
- `METHOD` - Installation method (default, template, etc.)
- `DIAGNOSTICS` - Enable telemetry (yes/no)
- `RANDOM_UUID` - Session UUID for tracking

**API Endpoint**: `http://api.community-scripts.org/dev/upload`

**Payload Structure**:
```json
{
    "ct_type": 1,                    // Privileged (1) or Unprivileged (0)
    "type": "lxc",                   // Always "lxc" for containers
    "disk_size": 8,                  // GB
    "core_count": 2,                 // CPU cores
    "ram_size": 2048,                // MB
    "os_type": "debian",             // OS name
    "os_version": "12",              // OS version
    "nsapp": "myapp",                // Application name
    "method": "default",             // Setup method
    "pve_version": "8.2.2",         // Proxmox VE version
    "status": "installing",          // Current status
    "random_id": "550e8400-e29b"    // Session UUID (anonymous)
}
```

**Usage Examples**:

```bash
# Example 1: Successful API post
CT_TYPE=1
DISK_SIZE=20
CORE_COUNT=4
RAM_SIZE=4096
var_os="ubuntu"
var_version="22.04"
NSAPP="jellyfin"
METHOD="default"
DIAGNOSTICS="yes"
RANDOM_UUID="550e8400-e29b-41d4-a716-446655440000"

post_to_api
# Result: Statistics sent to API (silently, no output)

# Example 2: Diagnostics disabled (opt-out)
DIAGNOSTICS="no"
post_to_api
# Result: Function returns immediately, no API call

# Example 3: Missing curl
DIAGNOSTICS="yes"
# curl not available in PATH
post_to_api
# Result: Function returns silently (curl requirement not met)
```

---

### `post_to_api_vm()`

**Purpose**: Sends VM creation statistics to Community-Scripts API (similar to post_to_api but for virtual machines).

**Signature**:
```bash
post_to_api_vm()
```

**Parameters**: None (uses global environment variables)

**Returns**: No explicit return value

**Requirements**: Same as `post_to_api()`

**Environment Variables Used**:
- `VMID` - Virtual machine ID
- `VM_TYPE` - VM type (kvm, etc.)
- `VM_CORES` - CPU core count
- `VM_RAM` - RAM in MB
- `VM_DISK` - Disk in GB
- `VM_OS` - Operating system
- `VM_VERSION` - OS version
- `VM_APP` - Application name
- `DIAGNOSTICS` - Enable telemetry
- `RANDOM_UUID` - Session UUID

**Payload Structure** (similar to containers but for VMs):
```json
{
    "vm_id": 100,
    "type": "qemu",
    "vm_cores": 4,
    "vm_ram": 4096,
    "vm_disk": 20,
    "vm_os": "ubuntu",
    "vm_version": "22.04",
    "vm_app": "jellyfin",
    "pve_version": "8.2.2",
    "status": "installing",
    "random_id": "550e8400-e29b"
}
```

---

### `post_update_to_api()`

**Purpose**: Reports installation completion status (success/failure) for container or VM.

**Signature**:
```bash
post_update_to_api()
```

**Parameters**: None (uses global environment variables)

**Returns**: No explicit return value

**Requirements**: Same as `post_to_api()`

**Environment Variables Used**:
- `RANDOM_UUID` - Session UUID (must match initial post_to_api call)
- `DIAGNOSTICS` - Enable telemetry
- Installation status parameters

**Payload Structure**:
```json
{
    "status": "completed",           // "completed" or "failed"
    "random_id": "550e8400-e29b",   // Session UUID
    "exit_code": 0,                  // 0 for success, error code for failure
    "error_explanation": ""          // Error description if failed
}
```

---

## API Payload Structure

### Container Creation Payload

```json
{
    "ct_type": 1,              // 1=Privileged, 0=Unprivileged
    "type": "lxc",             // Always "lxc"
    "disk_size": 20,           // GB
    "core_count": 4,           // CPU cores
    "ram_size": 4096,          // MB
    "os_type": "debian",       // Distribution name
    "os_version": "12",        // Version number
    "nsapp": "jellyfin",       // Application name
    "method": "default",       // Setup method
    "pve_version": "8.2.2",   // Proxmox VE version
    "status": "installing",    // Current phase
    "random_id": "550e8400"   // Unique session ID
}
```

### VM Creation Payload

```json
{
    "vm_id": 100,
    "type": "qemu",
    "vm_cores": 4,
    "vm_ram": 4096,
    "vm_disk": 20,
    "vm_os": "ubuntu",
    "vm_version": "22.04",
    "vm_app": "jellyfin",
    "pve_version": "8.2.2",
    "status": "installing",
    "random_id": "550e8400"
}
```

### Update/Completion Payload

```json
{
    "status": "completed",
    "random_id": "550e8400",
    "exit_code": 0,
    "error_explanation": ""
}
```

---

## Privacy & Opt-Out

### Privacy Policy

Community-Scripts telemetry is designed to be **privacy-respecting**:

- ✅ **Anonymous**: No personal data collected
- ✅ **Session-based**: UUID allows correlation without identification
- ✅ **Aggregated**: Only statistics are stored, never raw logs
- ✅ **Opt-out capable**: Single environment variable disables all telemetry
- ✅ **No tracking**: UUID cannot be linked to user identity
- ✅ **No credentials**: Passwords, SSH keys never transmitted

### Opt-Out Methods

**Method 1: Environment Variable (Single Script)**

```bash
DIAGNOSTICS="no" bash ct/myapp.sh
```

**Method 2: Script Header (Persistent)**

```bash
#!/bin/bash
export DIAGNOSTICS="no"
# Rest of script continues without telemetry
```

**Method 3: System-wide Configuration**

```bash
# In /etc/environment or ~/.bashrc
export DIAGNOSTICS="no"
```

### What Data Is Collected

| Data | Why | Shared? |
|------|-----|---------|
| Container/VM specs (cores, RAM, disk) | Understand deployment patterns | Yes, aggregated |
| OS type/version | Track popular distributions | Yes, aggregated |
| Application name | Understand popular apps | Yes, aggregated |
| Method (standard vs. custom) | Measure feature usage | Yes, aggregated |
| Success/failure status | Identify issues | Yes, aggregated |
| Exit codes | Debug failures | Yes, anonymized |

### What Data Is NOT Collected

- ❌ Container/VM hostnames
- ❌ IP addresses
- ❌ User credentials
- ❌ SSH keys or secrets
- ❌ Application data
- ❌ System logs
- ❌ Any personal information

---

## Error Mapping

### Mapping Strategy

Exit codes are categorized by source:

```
Exit Code Range | Source | Handling
0              | Success | Not reported to API
1-2            | Shell/Script | Generic error
100-101, 255   | Package managers | APT/DPKG specific
126-128        | Command execution | Permission/not found
130, 143       | Signals | User interrupt/termination
137, 139       | Kernel | OOM/segfault
200-231        | Proxmox custom | Container creation issues
210-212        | Python | Python environment issues
231-234        | PostgreSQL | Database connection issues
241-244        | MySQL/MariaDB | Database connection issues
243-249, 254   | Node.js/npm | Runtime errors
251-254        | MongoDB | Database connection issues
```

### Custom Exit Code Usage

Scripts can define custom exit codes:

```bash
# Example: Custom validation failure
if [[ "$CTID" -lt 100 ]]; then
  echo "Container ID must be >= 100"
  exit 205  # Custom Proxmox code
fi
```

---

## Best Practices

### 1. **Always Initialize RANDOM_UUID**

```bash
# Generate unique session ID for tracking
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"

# Use first 8 chars for short session ID (logs)
SESSION_ID="${RANDOM_UUID:0:8}"
BUILD_LOG="/tmp/create-lxc-${SESSION_ID}.log"
```

### 2. **Call post_to_api Early**

```bash
# Call post_to_api right after container creation starts
# This tracks attempt, even if installation fails

variables() {
  RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
  # ... other variables ...
}

# Later, in main script:
post_to_api  # Report container creation started
# ... perform installation ...
post_update_to_api  # Report completion
```

### 3. **Handle Graceful Failures**

```bash
# Wrap API calls to handle network issues
if command -v curl &>/dev/null; then
  post_to_api || true  # Don't fail if API unavailable
else
  msg_warn "curl not available, telemetry skipped"
fi
```

### 4. **Respect User Opt-Out**

```bash
# Check DIAGNOSTICS early and skip all API calls if disabled
if [[ "${DIAGNOSTICS}" != "yes" ]]; then
  msg_info "Anonymous diagnostics disabled"
  return 0  # Skip telemetry
fi
```

### 5. **Maintain Session Consistency**

```bash
# Use same RANDOM_UUID throughout lifecycle
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"

post_to_api         # Initial report
# ... installation ...
post_update_to_api  # Final report (same UUID links them)
```

---

## API Integration

### Connecting to API

The API endpoint is:

```
http://api.community-scripts.org/dev/upload
```

### API Response Handling

```bash
# Capture HTTP response code
RESPONSE=$(curl -s -w "%{http_code}" -L -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD") || true

# Extract status code (last 3 digits)
HTTP_CODE="${RESPONSE: -3}"

if [[ "$HTTP_CODE" == "200" ]]; then
  msg_ok "Telemetry submitted successfully"
elif [[ "$HTTP_CODE" == "429" ]]; then
  msg_warn "API rate limited, skipping telemetry"
else
  msg_info "Telemetry API unreachable (this is OK)"
fi
```

### Network Resilience

API calls are **best-effort** and never block installation:

```bash
# Telemetry should never cause container creation to fail
if post_to_api 2>/dev/null; then
  msg_info "Diagnostics transmitted"
fi
# If API unavailable, continue anyway
```

---

## Contributing

### Adding New Exit Codes

1. Document in the appropriate category section
2. Update `explain_exit_code()` in both api.func and error_handler.func
3. Add recovery suggestions
4. Test mapping with scripts that use the new code

### Testing API Integration

```bash
# Test with mock curl (local testing)
DIAGNOSTICS="yes"
RANDOM_UUID="test-uuid-12345678"
curl -X POST http://localhost:8000/dev/upload \
  -H "Content-Type: application/json" \
  -d '{"test": "payload"}'

# Verify payload structure
post_to_api 2>&1 | head -20
```

### Telemetry Reporting Improvements

Suggestions for improvement:

1. Installation duration tracking
2. Package version compatibility data
3. Feature usage analytics
4. Performance metrics
5. Custom error codes

---

## Notes

- API calls are **silent by default** and never display sensitive information
- Telemetry can be **completely disabled** via `DIAGNOSTICS="no"`
- **RANDOM_UUID must be generated** before calling any post functions
- Exit code mappings are **shared** between api.func and error_handler.func for consistency
- API is **optional** - containers work perfectly without telemetry

