# Error-Handler.func Wiki

Comprehensive error handling and signal management module providing exit code explanations, error handlers with logging, and signal trap configuration for all Community-Scripts projects.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Exit Code Reference](#exit-code-reference)
- [Error Handler Functions](#error-handler-functions)
- [Signal Traps](#signal-traps)
- [Initialization & Setup](#initialization--setup)
- [Error Logging](#error-logging)
- [Best Practices](#best-practices)
- [Debugging](#debugging)
- [Contributing](#contributing)

---

## Overview

The error_handler.func module provides robust error handling infrastructure:

- ✅ Comprehensive exit code mapping (1-255+ codes documented)
- ✅ Detailed error messages with line numbers and commands
- ✅ Signal trap configuration (ERR, EXIT, INT, TERM, RETURN)
- ✅ Error logging to persistent files
- ✅ Graceful cleanup on signal termination
- ✅ Stack trace display for debugging
- ✅ Integration with core.func message functions
- ✅ Container-agnostic (works in Proxmox + LXC)

### Error Handling Flow

```
Command Execution
      ↓
   ERROR (non-zero exit)
      ↓
  ERR Trap Triggered
      ↓
error_handler() called
      ↓
explain_exit_code() lookup
      ↓
Display error with line/command
      ↓
Check for log file
      ↓
Exit with original code
```

---

## Exit Code Reference

Exit codes are categorized by source system. See `api.func.md` for comprehensive mapping documentation.

### Quick Reference Table

| Range | Category | Examples |
|-------|----------|----------|
| 0 | Success | (no error) |
| 1-2 | Shell errors | Syntax error, operation not permitted |
| 100-101 | APT errors | Package manager errors |
| 126-139 | System errors | Command not found, segfault, OOM |
| 200-231 | Proxmox custom | Container creation errors |
| 210-234 | Database errors | PostgreSQL, MySQL connection issues |
| 243-254 | Runtime errors | Node.js, Python, npm errors |
| 255 | DPKG fatal | Package system fatal error |

---

## Error Handler Functions

### `explain_exit_code()`

**Purpose**: Maps numeric exit codes to human-readable descriptions. Shared with api.func for consistency.

**Signature**:
```bash
explain_exit_code()
```

**Parameters**:
- `$1` - Exit code (0-255+)

**Returns**: Human-readable explanation string

**Categories Handled**:
- Generic shell errors (1, 2, 126-128, 130, 137, 139, 143)
- Package managers (100-101, 255)
- Python (210-212)
- Databases (PostgreSQL 231-234, MySQL 241-244, MongoDB 251-254)
- Node.js/npm (243-249, 254)
- Proxmox custom (200-231)
- Default: "Unknown error"

**Usage Examples**:

```bash
# Example 1: Look up error code
explain_exit_code 127
# Output: "Command not found"

# Example 2: In error logging
error_desc=$(explain_exit_code "$exit_code")
echo "Error: $error_desc" >> /tmp/error.log

# Example 3: Unknown code
explain_exit_code 999
# Output: "Unknown error"
```

---

### `error_handler()`

**Purpose**: Main error handler triggered by ERR trap. Displays detailed error information and exits.

**Signature**:
```bash
error_handler()
```

**Parameters**:
- `$1` (optional) - Exit code (default: current $?)
- `$2` (optional) - Command that failed (default: $BASH_COMMAND)
- `$3` (optional) - Line number (default: ${BASH_LINENO[0]})

**Returns**: Exits with original exit code (does not return)

**Output Format**:
```
[ERROR] in line 42: exit code 1 (General error): while executing command curl https://api.example.com

--- Last 10 lines of log file ---
[log content]
------------------------------------
```

**Implementation Pattern**:
```bash
error_handler() {
  local exit_code=${1:-$?}
  local command=${2:-${BASH_COMMAND:-unknown}}
  local line_number=${BASH_LINENO[0]:-unknown}

  # If successful, return silently
  if [[ "$exit_code" -eq 0 ]]; then
    return 0
  fi

  # Get human-readable error description
  local explanation=$(explain_exit_code "$exit_code")

  # Show cursor (might be hidden by spinner)
  printf "\e[?25h"

  # Display error using color messages
  if declare -f msg_error >/dev/null 2>&1; then
    msg_error "in line ${line_number}: exit code ${exit_code} (${explanation}): while executing command ${command}"
  else
    echo -e "\n${RD}[ERROR]${CL} in line ${line_number}: exit code ${exit_code}: ${command}\n"
  fi

  # Log error details if log file configured
  if [[ -n "${DEBUG_LOGFILE:-}" ]]; then
    {
      echo "------ ERROR ------"
      echo "Timestamp : $(date '+%Y-%m-%d %H:%M:%S')"
      echo "Exit Code : $exit_code ($explanation)"
      echo "Line      : $line_number"
      echo "Command   : $command"
      echo "-------------------"
    } >> "$DEBUG_LOGFILE"
  fi

  # Show last lines of log if available
  local active_log="$(get_active_logfile)"
  if [[ -s "$active_log" ]]; then
    local log_lines=$(wc -l < "$active_log")
    echo "--- Last 10 lines of log ---"
    tail -n 10 "$active_log"
    echo "----------------------------"
  fi

  exit "$exit_code"
}
```

**Usage Examples**:

```bash
# Example 1: Automatic trap (recommended)
trap 'error_handler $? "$BASH_COMMAND" $LINENO' ERR
# Error automatically caught and handled

# Example 2: Manual invocation (testing)
error_handler 1 "curl https://api.example.com" 42
# Output: Detailed error with line number

# Example 3: In conditional
if ! some_command; then
  error_handler $? "some_command" $LINENO
fi
```

---

## Signal Traps

### `on_exit()`

**Purpose**: Cleanup handler called on normal script exit or error.

**Signature**:
```bash
on_exit()
```

**Parameters**: None

**Returns**: Exits with captured exit code

**Behavior**:
- Captures current exit code
- Removes lock files if present
- Exits with original exit code

**Implementation Pattern**:
```bash
on_exit() {
  local exit_code="$?"

  # Cleanup lock files
  [[ -n "${lockfile:-}" && -e "$lockfile" ]] && rm -f "$lockfile"

  # Preserve exit code
  exit "$exit_code"
}
```

**Trap Configuration**:
```bash
trap on_exit EXIT  # Always called on exit
```

---

### `on_interrupt()`

**Purpose**: Handler for Ctrl+C (SIGINT) signal. Allows graceful shutdown.

**Signature**:
```bash
on_interrupt()
```

**Parameters**: None

**Returns**: Exits with code 130 (standard SIGINT exit code)

**Output**: Displays "Interrupted by user (SIGINT)" message

**Implementation Pattern**:
```bash
on_interrupt() {
  echo -e "\n${RD}Interrupted by user (SIGINT)${CL}"
  exit 130
}
```

**Trap Configuration**:
```bash
trap on_interrupt INT  # Called on Ctrl+C
```

**Usage Example**:
```bash
# Script interrupted by user:
# Ctrl+C pressed
# → on_interrupt() triggers
# → "Interrupted by user (SIGINT)" displayed
# → Exit with code 130
```

---

### `on_terminate()`

**Purpose**: Handler for SIGTERM signal. Allows graceful shutdown on termination.

**Signature**:
```bash
on_terminate()
```

**Parameters**: None

**Returns**: Exits with code 143 (standard SIGTERM exit code)

**Output**: Displays "Terminated by signal (SIGTERM)" message

**Implementation Pattern**:
```bash
on_terminate() {
  echo -e "\n${RD}Terminated by signal (SIGTERM)${CL}"
  exit 143
}
```

**Trap Configuration**:
```bash
trap on_terminate TERM  # Called on SIGTERM
```

**Usage Example**:
```bash
# System sends SIGTERM:
# kill -TERM $PID executed
# → on_terminate() triggers
# → "Terminated by signal (SIGTERM)" displayed
# → Exit with code 143
```

---

## Initialization & Setup

### `catch_errors()`

**Purpose**: Sets up all error traps and signal handlers. Called once at script start.

**Signature**:
```bash
catch_errors()
```

**Parameters**: None

**Returns**: No explicit return value (configures traps)

**Traps Configured**:
1. `ERR` → `error_handler()` - Catches command failures
2. `EXIT` → `on_exit()` - Cleanup on any exit
3. `INT` → `on_interrupt()` - Handle Ctrl+C
4. `TERM` → `on_terminate()` - Handle SIGTERM
5. `RETURN` → `error_handler()` - Catch function errors

**Implementation Pattern**:
```bash
catch_errors() {
  # Set strict mode
  set -Eeuo pipefail

  # Configure traps
  trap 'error_handler $? "$BASH_COMMAND" $LINENO' ERR
  trap on_exit EXIT
  trap on_interrupt INT
  trap on_terminate TERM
  trap 'error_handler $? "$BASH_COMMAND" $LINENO' RETURN
}
```

**Usage Examples**:

```bash
# Example 1: Alpine container script
#!/bin/sh
source <(curl -fsSL .../core.func)
source <(curl -fsSL .../error_handler.func)
load_functions
catch_errors

# Now all signals handled automatically
update_os

# Example 2: Proxmox host script
#!/bin/bash
source <(curl -fsSL .../core.func)
source <(curl -fsSL .../error_handler.func)
load_functions
catch_errors

# Safe to proceed with error handling
create_container
```

---

## Error Logging

### Log File Configuration

**Active Log Detection**:
```bash
# In build.func/install.func:
BUILD_LOG="/tmp/create-lxc-${SESSION_ID}.log"
INSTALL_LOG="/root/install-${SESSION_ID}.log"
SILENT_LOGFILE="$(get_active_logfile)"  # Points to appropriate log
```

### Log Output Behavior

When command fails in `silent()`:

1. Last 10 lines of log file are displayed
2. Full log path shown if more than 10 lines
3. Error message includes line number where failure occurred
4. Command that failed is displayed

### Accessing Error Logs

From Proxmox host:
```bash
# Host-side container creation log
/tmp/create-lxc-<SESSION_ID>.log

# View error details
tail -50 /tmp/create-lxc-550e8400.log
grep ERROR /tmp/create-lxc-*.log

# Development mode persistent logs
/var/log/community-scripts/create-lxc-<SESSION_ID>-<TIMESTAMP>.log
```

From inside LXC container:
```bash
# Container installation log
/root/install-<SESSION_ID>.log

# View recent errors
tail -20 /root/install-550e8400.log
```

---

## Best Practices

### 1. **Always Setup Traps Early**

```bash
#!/bin/bash
set -Eeuo pipefail

source <(curl -fsSL .../core.func)
source <(curl -fsSL .../error_handler.func)
load_functions
catch_errors  # MUST be called before any real work

# Now safe - all signals handled
```

### 2. **Use Meaningful Error Exit Codes**

```bash
# Use Proxmox custom codes for container-specific errors
if [[ "$CTID" -lt 100 ]]; then
  msg_error "Container ID must be >= 100"
  exit 205  # Proxmox custom code
fi

# Use standard codes for common errors
if ! command -v curl &>/dev/null; then
  msg_error "curl not installed"
  exit 127  # Command not found
fi
```

### 3. **Log Context Information**

```bash
# In error_handler, DEBUG_LOGFILE receives:
DEBUG_LOGFILE="/tmp/debug.log"

# All errors logged with timestamp and details
{
  echo "Error at $(date)"
  echo "Exit code: $exit_code"
  echo "Command: $command"
} >> "$DEBUG_LOGFILE"
```

### 4. **Graceful Signal Handling**

```bash
# Setup signal handlers for cleanup
cleanup() {
  [[ -f "$temp_file" ]] && rm -f "$temp_file"
  [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"
}
trap cleanup EXIT

# Now temporary files always cleaned up
```

### 5. **Test Error Paths**

```bash
# Force error for testing
false  # Triggers error_handler
# or
exit 1  # Custom error

# Verify error handling works correctly
# Check log files and messages
```

---

## Debugging

### Enable Stack Trace

```bash
# Via environment variable
DEV_MODE_TRACE=true bash script.sh

# Or in script
set -x  # Show all commands
trap 'error_handler $? "$BASH_COMMAND" $LINENO' ERR
```

### View Full Error Context

```bash
# Show full log file instead of last 10 lines
DEBUG_LOGFILE="/tmp/full-debug.log"

# After error, review complete context
less /tmp/full-debug.log
```

### Test Error Handler

```bash
# Manually trigger error handler
bash -c 'source <(curl -fsSL .../error_handler.func); catch_errors; exit 42'

# Should display:
# [ERROR] in line N: exit code 42 (Unknown error): ...
```

---

## Contributing

### Adding New Error Codes

1. Assign code in appropriate range (see Exit Code Reference)
2. Add description to `explain_exit_code()` in both:
   - error_handler.func
   - api.func (for consistency)
3. Document in exit code table
4. Update error mapping documentation

### Improving Error Messages

Example: Make error message more helpful:

```bash
# Before:
"Container ID must be >= 100"

# After:
"Invalid CTID: $CTID. Container IDs must be >= 100. Current range: 100-999"
```

### Testing Signal Handlers

```bash
# Test INT signal (Ctrl+C)
bash -c 'source <(curl -fsSL .../error_handler.func); catch_errors; sleep 30' &
PID=$!
sleep 1
kill -INT $PID
wait

# Test TERM signal
bash -c 'source <(curl -fsSL .../error_handler.func); catch_errors; sleep 30' &
PID=$!
sleep 1
kill -TERM $PID
wait
```

---

## Notes

- Error handler is **required** for all scripts (ensures safe cleanup)
- Exit codes are **standardized** (0 = success, 1-255 = specific errors)
- Signals are **trapped** to allow graceful shutdown
- Lock files are **automatically cleaned** on exit
- Log files contain **full error context** for debugging

