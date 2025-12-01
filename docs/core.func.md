# Core.func Wiki

The foundational utility library providing colors, formatting, validation checks, message output, and execution helpers used across all Community-Scripts ecosystem projects.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Initialization Functions](#initialization-functions)
- [Color & Formatting](#color--formatting)
- [Validation Checks](#validation-checks)
- [Message Output Functions](#message-output-functions)
- [Execution Helpers](#execution-helpers)
- [Development Mode](#development-mode)
- [Best Practices](#best-practices)
- [Contributing](#contributing)

---

## Overview

Core.func provides essential utilities for consistent behavior across all Community-Scripts:

- ✅ ANSI color codes for styled terminal output
- ✅ Standard icons and formatting for UI consistency
- ✅ System validation checks (root, PVE version, architecture)
- ✅ Colored message functions (info, ok, error, warn)
- ✅ Silent command execution with log redirection
- ✅ Spinner animations for long-running operations
- ✅ Development mode support (trace, breakpoint, dry-run)
- ✅ Guard clauses to prevent reloading

### Integration Pattern

```bash
#!/bin/bash
source <(curl -fsSL https://git.community-scripts.org/.../core.func)
load_functions     # Initialize all color/formatting/defaults
root_check         # Validate prerequisites
pve_check          # Check Proxmox VE version
```

---

## Initialization Functions

### `load_functions()`

**Purpose**: Initializes all core utility function groups. Must be called once before using any core utilities.

**Signature**:
```bash
load_functions()
```

**Parameters**: None

**Returns**: No explicit return value (sets global variables)

**Guard Mechanism**:
```bash
[[ -n "${__FUNCTIONS_LOADED:-}" ]] && return  # Prevent re-loading
_CORE_FUNC_LOADED=1  # Mark as loaded
```

**Initializes** (in order):
1. `color()` - ANSI color codes
2. `formatting()` - Text formatting helpers
3. `icons()` - Emoji/symbol constants
4. `default_vars()` - Retry and timeout settings
5. `set_std_mode()` - Verbose/silent mode

**Usage Examples**:

```bash
# Example 1: Typical initialization
source <(curl -fsSL .../core.func)
load_functions      # Safe to call multiple times
msg_info "Starting setup"  # Now colors are available

# Example 2: Safe multiple sourcing
source <(curl -fsSL .../core.func)
load_functions
source <(curl -fsSL .../tools.func)
load_functions      # Silently returns (already loaded)
```

---

### `color()`

**Purpose**: Defines ANSI escape codes for colored terminal output.

**Signature**:
```bash
color()
```

**Color Variables Defined**:

| Variable | Code | Effect | Use Case |
|----------|------|--------|----------|
| `YW` | `\033[33m` | Yellow | Warnings, secondary info |
| `YWB` | `\e[93m` | Bright Yellow | Emphasis, bright warnings |
| `BL` | `\033[36m` | Cyan/Blue | Hostnames, IPs, values |
| `RD` | `\033[01;31m` | Bright Red | Errors, critical alerts |
| `GN` | `\033[1;92m` | Bright Green | Success, OK status |
| `DGN` | `\033[32m` | Dark Green | Background, secondary success |
| `BGN` | `\033[4;92m` | Green with underline | Highlights |
| `CL` | `\033[m` | Clear | Reset to default |

**Usage Examples**:

```bash
# Example 1: Colored output
color
echo -e "${RD}Error: File not found${CL}"
# Output: "Error: File not found" (in red)

# Example 2: Multiple colors on one line
echo -e "${YW}Warning:${CL} ${BL}$HOSTNAME${CL} is running low on ${RD}RAM${CL}"

# Example 3: In functions
print_status() {
  echo -e "${GN}✓${CL} Operation completed"
}
```

---

### `formatting()`

**Purpose**: Defines formatting helpers for terminal output.

**Signature**:
```bash
formatting()
```

**Formatting Variables Defined**:

| Variable | Escape Code | Purpose |
|----------|------------|---------|
| `BFR` | `\r\033[K` | Backspace and clear line |
| `BOLD` | `\033[1m` | Bold text |
| `HOLD` | ` ` (space) | Spacing |
| `TAB` | `  ` (2 spaces) | Indentation |
| `TAB3` | `      ` (6 spaces) | Larger indentation |

**Usage Examples**:

```bash
# Example 1: Overwrite previous line (progress)
for i in {1..10}; do
  echo -en "${BFR}Progress: $i/10"
  sleep 1
done

# Example 2: Bold emphasis
echo -e "${BOLD}Important:${CL} This requires attention"

# Example 3: Structured indentation
echo "Main Item:"
echo -e "${TAB}Sub-item 1"
echo -e "${TAB}Sub-item 2"
```

---

### `icons()`

**Purpose**: Defines symbolic emoji and icon constants used for UI consistency.

**Signature**:
```bash
icons()
```

**Icon Variables Defined**:

| Variable | Icon | Use |
|----------|------|-----|
| `CM` | ✔️ | Success/checkmark |
| `CROSS` | ✖️ | Error/cross |
| `INFO` | 💡 | Information |
| `OS` | 🖥️ | Operating system |
| `CONTAINERTYPE` | 📦 | Container |
| `DISKSIZE` | 💾 | Disk/storage |
| `CPUCORE` | 🧠 | CPU |
| `RAMSIZE` | 🛠️ | RAM |
| `HOSTNAME` | 🏠 | Hostname |
| `BRIDGE` | 🌉 | Network bridge |
| `NETWORK` | 📡 | Network |
| `GATEWAY` | 🌐 | Gateway |
| `CREATING` | 🚀 | Creating |
| `ADVANCED` | 🧩 | Advanced/options |
| `HOURGLASS` | ⏳ | Wait/timer |

---

### `default_vars()`

**Purpose**: Sets default retry and timing variables for system operations.

**Signature**:
```bash
default_vars()
```

**Variables Set**:
- `RETRY_NUM=10` - Maximum retry attempts
- `RETRY_EVERY=3` - Seconds between retries
- `i=$RETRY_NUM` - Counter for retry loops

**Usage Examples**:

```bash
# Example 1: Retry loop with defaults
RETRY_NUM=10
RETRY_EVERY=3
i=$RETRY_NUM
while [ $i -gt 0 ]; do
  if check_network; then
    break
  fi
  echo "Retrying... ($i attempts left)"
  sleep $RETRY_EVERY
  i=$((i - 1))
done

# Example 2: Custom retry values
RETRY_NUM=5  # Try 5 times
RETRY_EVERY=2  # Wait 2 seconds between attempts
```

---

### `set_std_mode()`

**Purpose**: Configures output verbosity and optional debug tracing based on environment variables.

**Signature**:
```bash
set_std_mode()
```

**Behavior**:
- If `VERBOSE=yes`: `STD=""` (show all output)
- If `VERBOSE=no`: `STD="silent"` (suppress output via silent() wrapper)
- If `DEV_MODE_TRACE=true`: Enable `set -x` bash tracing

**Variables Set**:
- `STD` - Command prefix for optional output suppression

**Usage Examples**:

```bash
# Example 1: Verbose output
VERBOSE="yes"
set_std_mode
$STD apt-get update  # Shows all apt output
# Output: All package manager messages displayed

# Example 2: Silent output
VERBOSE="no"
set_std_mode
$STD apt-get update  # Silently updates, logs to file
# Output: Only progress bar or errors shown

# Example 3: Debug tracing
DEV_MODE_TRACE="true"
set_std_mode
# bash shows every command before executing: +(script.sh:123): function_name(): cmd
```

---

### `parse_dev_mode()`

**Purpose**: Parses comma-separated dev_mode string to enable development features.

**Signature**:
```bash
parse_dev_mode()
```

**Parameters**: None (uses `$dev_mode` environment variable)

**Supported Flags**:
- `motd` - Setup SSH/MOTD before installation
- `keep` - Never delete container on failure
- `trace` - Enable bash set -x tracing
- `pause` - Pause after each msg_info step
- `breakpoint` - Open shell on error instead of cleanup
- `logs` - Persist logs to /var/log/community-scripts/
- `dryrun` - Show commands without executing

**Environment Variables Set**:
- `DEV_MODE_MOTD=false|true`
- `DEV_MODE_KEEP=false|true`
- `DEV_MODE_TRACE=false|true`
- `DEV_MODE_PAUSE=false|true`
- `DEV_MODE_BREAKPOINT=false|true`
- `DEV_MODE_LOGS=false|true`
- `DEV_MODE_DRYRUN=false|true`

**Usage Examples**:

```bash
# Example 1: Enable debugging
dev_mode="trace,logs"
parse_dev_mode
# Enables bash tracing and persistent logging

# Example 2: Keep container on error
dev_mode="keep,breakpoint"
parse_dev_mode
# Container never deleted on error, opens shell at breakpoint

# Example 3: Multiple modes
dev_mode="motd,keep,trace,pause"
parse_dev_mode
# All four development modes active
```

---

## Color & Formatting

### Color Codes

**Standard Colors**:
```bash
${YW}   # Yellow (warnings)
${RD}   # Red (errors)
${GN}   # Green (success)
${BL}   # Blue/Cyan (values)
${CL}   # Clear (reset)
```

**Example Combinations**:
```bash
echo -e "${YW}Warning:${CL} ${RD}Critical${CL} at ${BL}$(date)${CL}"
# Output: "Warning: Critical at 2024-12-01 10:30:00" (colored appropriately)
```

---

## Validation Checks

### `shell_check()`

**Purpose**: Verifies script is running under Bash (not sh, dash, etc.).

**Signature**:
```bash
shell_check()
```

**Parameters**: None

**Returns**: 0 if Bash; exits with error if not

**Behavior**:
- Checks `ps -p $$ -o comm=` (current shell command)
- Exits with error message if not "bash"
- Clears screen for better error visibility

**Usage Examples**:

```bash
#!/bin/bash
source <(curl -fsSL .../core.func)
load_functions
shell_check  # Exits if run with: sh script.sh or dash script.sh

# If run correctly: bash script.sh - continues
# If run with sh: Displays error and exits
```

---

### `root_check()`

**Purpose**: Verifies script is running with root privileges directly (not via sudo).

**Signature**:
```bash
root_check()
```

**Parameters**: None

**Returns**: 0 if root directly; exits with error if not

**Checks**:
- `id -u` must be 0 (root)
- Parent process (`$PPID`) must not be "sudo"

**Why**: Some scripts require genuine root context, not sudo-elevated user shell.

**Usage Examples**:

```bash
#!/bin/bash
# Must run as root directly, not via sudo
source <(curl -fsSL .../core.func)
load_functions
root_check  # Will fail if: sudo bash script.sh

# Correct: bash script.sh (from root shell on Proxmox)
```

---

### `pve_check()`

**Purpose**: Validates Proxmox VE version compatibility.

**Signature**:
```bash
pve_check()
```

**Parameters**: None

**Returns**: 0 if supported version; exits with error if not

**Supported Versions**:
- PVE 8.0 - 8.9
- PVE 9.0 - 9.1

**Version Detection**:
```bash
PVE_VER=$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')
# Example: "pveversion" → "pve-manager/8.2.2/550e8400-e29b"
#          Extracted: "8.2.2" → "8"
```

**Usage Examples**:

```bash
# Example 1: On supported PVE 8.2
bash ct/app.sh
# Passes: 8.2 is in range 8.0-8.9

# Example 2: On unsupported PVE 7.4
bash ct/app.sh
# Error: "This version of Proxmox VE is not supported"

# Example 3: On future unsupported PVE 10.0
bash ct/app.sh
# Error: "This version of Proxmox VE is not yet supported"
```

---

### `arch_check()`

**Purpose**: Validates system architecture is amd64/x86_64 (not ARM/PiMox).

**Signature**:
```bash
arch_check()
```

**Parameters**: None

**Returns**: 0 if amd64; exits with error if not

**Behavior**:
- Checks `dpkg --print-architecture`
- Exits if not "amd64"
- Provides link to ARM64-compatible scripts

**Usage Examples**:

```bash
# Example 1: On x86_64 server
arch_check
# Passes silently

# Example 2: On PiMox (ARM64)
arch_check
# Error: "This script will not work with PiMox!"
# Suggests: https://github.com/asylumexp/Proxmox
```

---

### `ssh_check()`

**Purpose**: Detects SSH connection and warns if connecting remotely (recommends Proxmox console).

**Signature**:
```bash
ssh_check()
```

**Parameters**: None

**Returns**: No explicit return value (warning only, does not exit)

**Behavior**:
- Checks `$SSH_CLIENT` environment variable
- Analyzes client IP to determine if local or remote
- Skips warning for local/same-subnet connections
- Warns for external connections

**Usage Examples**:

```bash
# Example 1: Local SSH (Proxmox WebUI console)
ssh_check
# No warning: Client is localhost (127.0.0.1)

# Example 2: External SSH over Internet
ssh -l root 1.2.3.4 "bash script.sh"
# Warning: "Running via external SSH (client: 1.2.3.4)"
# Recommends Proxmox Shell (Console) instead
```

---

## Message Output Functions

### `msg_info()`

**Purpose**: Displays informational message with icon and yellow color.

**Signature**:
```bash
msg_info()
```

**Parameters**:
- `$@` - Message text (concatenated with spaces)

**Format**: `[ℹ️] Message text` (yellow)

**Usage Examples**:

```bash
msg_info "Starting container setup"
# Output: ℹ️  Starting container setup

msg_info "Updating OS packages" "for debian:12"
# Output: ℹ️  Updating OS packages for debian:12
```

---

### `msg_ok()`

**Purpose**: Displays success message with checkmark and green color.

**Signature**:
```bash
msg_ok()
```

**Parameters**:
- `$@` - Message text

**Format**: `[✔️] Message text` (green)

**Usage Examples**:

```bash
msg_ok "Container created"
# Output: ✔️  Container created (in green)

msg_ok "Network Connected: 10.0.3.50"
# Output: ✔️  Network Connected: 10.0.3.50
```

---

### `msg_error()`

**Purpose**: Displays error message with cross icon and red color. Does not exit.

**Signature**:
```bash
msg_error()
```

**Parameters**:
- `$@` - Message text

**Format**: `[✖️] Message text` (red)

**Usage Examples**:

```bash
msg_error "Container ID already in use"
# Output: ✖️  Container ID already in use (in red)
```

---

### `msg_warn()`

**Purpose**: Displays warning message with yellow color.

**Signature**:
```bash
msg_warn()
```

**Parameters**:
- `$@` - Message text

**Format**: `[⚠️] Message text` (yellow/orange)

**Usage Examples**:

```bash
msg_warn "This will delete all data"
# Output: ⚠️  This will delete all data
```

---

## Execution Helpers

### `silent()`

**Purpose**: Executes command with output redirected to log file. On error: displays last 10 lines of log and exits.

**Signature**:
```bash
silent()
```

**Parameters**:
- `$@` - Command and arguments to execute

**Returns**: 0 on success; exits with original error code on failure

**Environment Effects**:
- Temporarily disables `set -e` and error trap to capture exit code
- Re-enables after command completes
- Logs to `$BUILD_LOG` or `$INSTALL_LOG`

**Log Display On Error**:
```bash
--- Last 10 lines of silent log ---
[log output]
-----------------------------------
```

**Usage Examples**:

```bash
# Example 1: Suppress package manager output
silent apt-get update
# Output: suppressed, logged to file

# Example 2: Conditional display on error
silent curl -fsSL https://api.example.com
# If curl fails: shows last 10 log lines and exits

# Example 3: Verbose mode shows everything
VERBOSE="yes"
silent apt-get update  # Shows all output (STD is empty)
```

---

### `spinner()`

**Purpose**: Displays animated spinner with rotating characters during long operations.

**Signature**:
```bash
spinner()
```

**Parameters**: None (uses `$SPINNER_MSG` environment variable)

**Animation**:
```
⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏ (repeating)
```

**Environment Variables**:
- `SPINNER_MSG` - Text to display with spinner

**Lifecycle**:
```bash
# Start spinner in background
SPINNER_MSG="Downloading..."
spinner &
SPINNER_PID=$!

# ... do long operation ...

# Stop spinner
stop_spinner

echo "Done!"
```

**Usage Examples**:

```bash
# Example 1: Long operation with spinner
SPINNER_MSG="Building container..."
spinner &
SPINNER_PID=$!

sleep 10  # Simulate work

stop_spinner
msg_ok "Container created"
```

---

### `clear_line()`

**Purpose**: Clears current terminal line and moves cursor to beginning.

**Signature**:
```bash
clear_line()
```

**Parameters**: None

**Implementation**: Uses `tput` or ANSI escape codes

**Usage Examples**:

```bash
for file in *.sh; do
  echo -n "Processing $file..."
  process_file "$file"
  clear_line
done
# Each file overwrites previous line
```

---

### `stop_spinner()`

**Purpose**: Stops running spinner process and cleans up temporary files.

**Signature**:
```bash
stop_spinner()
```

**Parameters**: None (reads `$SPINNER_PID` or `/tmp/.spinner.pid`)

**Cleanup**:
- Graceful kill of spinner process
- Force kill (-9) if needed
- Removes `/tmp/.spinner.pid` temp file
- Resets terminal state

**Usage Examples**:

```bash
# Example 1: Simple stop
spinner &
SPINNER_PID=$!
sleep 5
stop_spinner

# Example 2: In trap handler
trap 'stop_spinner' EXIT
spinner &
```

---

## Development Mode

### Enabling Development Features

**Via Environment Variable**:
```bash
dev_mode="trace,keep,breakpoint" bash ct/myapp.sh
```

**Via Script Header**:
```bash
#!/bin/bash
export dev_mode="trace,logs,pause"
source <(curl -fsSL .../core.func)
load_functions
parse_dev_mode
```

### Available Modes

| Mode | Effect |
|------|--------|
| `trace` | Enable bash -x tracing (verbose command logging) |
| `keep` | Never delete container on error (for debugging) |
| `logs` | Persist all logs to /var/log/community-scripts/ |
| `pause` | Pause after each msg_info step (manual stepping) |
| `breakpoint` | Open shell on error instead of immediate cleanup |
| `motd` | Configure SSH/MOTD before installation starts |
| `dryrun` | Show commands without executing them |

---

## Best Practices

### 1. **Always Call load_functions() First**

```bash
#!/bin/bash
set -Eeuo pipefail

source <(curl -fsSL .../core.func)
load_functions  # MUST be before using any color variables

msg_info "Starting setup"  # Now safe to use
```

### 2. **Use Message Functions Consistently**

```bash
msg_info "Starting step"
# Do work...
msg_ok "Step completed"

# Or on error:
if ! command; then
  msg_error "Command failed"
  exit 1
fi
```

### 3. **Combine Validation Checks**

```bash
#!/bin/bash
source <(curl -fsSL .../core.func)
load_functions

shell_check   # Exits if wrong shell
root_check    # Exits if not root
pve_check     # Exits if unsupported version
arch_check    # Exits if wrong architecture

# All checks passed, safe to proceed
msg_ok "Pre-flight checks passed"
```

### 4. **Use Verbose Mode for Debugging**

```bash
VERBOSE="yes" bash ct/myapp.sh
# Shows all silent() command output for troubleshooting
```

### 5. **Log Important Operations**

```bash
silent apt-get update        # Suppress unless error
msg_ok "Packages updated"    # Show success
silent systemctl start nginx # Suppress unless error
msg_ok "Nginx started"       # Show success
```

---

## Contributing

### Adding New Message Functions

Follow existing pattern:

```bash
msg_custom() {
  local icon="$1"
  local color="$2"
  local message="$3"
  echo -e "${TAB}${icon}${TAB}${color}${message}${CL}"
}
```

### Adding Color Support

New colors should follow semantic naming:

```bash
BG_ERROR=$'\e[41m'   # Red background for errors
BG_SUCCESS=$'\e[42m' # Green background for success
```

### Testing Color Output

```bash
bash
source <(curl -fsSL .../core.func)
load_functions

echo -e "${YW}Yellow${CL} ${RD}Red${CL} ${GN}Green${CL} ${BL}Blue${CL}"
```

---

## Notes

- Core.func is designed to be **sourced once** and **loaded everywhere**
- All color variables are **ANSI escape codes** (work in all terminals)
- Messages use **emoji icons** for visual consistency
- Validation checks use **standard exit codes** (0 for success, 1 for error)
- The module is **lightweight** and loads instantly

