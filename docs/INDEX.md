# 📚 ProxmoxVED Documentation Index

Complete guide to all ProxmoxVED documentation - quickly find what you need.

---

## 🎯 **Quick Navigation by Goal**

### 👤 **I want to...**

**Contribute a new application**
→ Start with: [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md)
→ Then: [UPDATED_APP-ct.md](UPDATED_APP-ct.md) + [UPDATED_APP-install.md](UPDATED_APP-install.md)

**Understand the architecture**
→ Read: [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md)
→ Then: [misc/README.md](misc/README.md)

**Debug a failed installation**
→ Check: [EXIT_CODES.md](EXIT_CODES.md)
→ Then: [DEV_MODE.md](DEV_MODE.md)
→ See also: [misc/error_handler.func/](misc/error_handler.func/)

**Configure system defaults**
→ Read: [DEFAULTS_SYSTEM_GUIDE.md](DEFAULTS_SYSTEM_GUIDE.md)

**Learn about recent changes**
→ Check: [CHANGELOG_MISC.md](CHANGELOG_MISC.md)

**Develop a function library**
→ Study: [misc/](misc/) documentation

---

## 📂 **Documentation by Category**

### 🏗️ **Project Structure Documentation**

| Directory | Documentation |
|-----------|---|
| **[/ct](ct/)** | Container creation scripts documentation |
| **[/install](install/)** | Installation scripts documentation |
| **[/vm](vm/)** | Virtual machine creation scripts documentation |
| **[/tools](tools/)** | Tools and utilities documentation |
| **[/api](api/)** | API integration documentation |
| **[/misc](misc/)** | Function libraries (9 total) |

### 🚀 **For Contributors**

| Document | Purpose |
|----------|---------|
| [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md) | Complete contribution workflow |
| [UPDATED_APP-ct.md](UPDATED_APP-ct.md) | How to write ct/AppName.sh scripts |
| [UPDATED_APP-install.md](UPDATED_APP-install.md) | How to write install/appname-install.sh scripts |
| [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md) | System architecture deep-dive |

### 🔧 **For Operators & Developers**

| Document | Purpose |
|----------|---------|
| [EXIT_CODES.md](EXIT_CODES.md) | Complete exit code reference |
| [DEV_MODE.md](DEV_MODE.md) | Debugging and development modes |
| [DEFAULTS_SYSTEM_GUIDE.md](DEFAULTS_SYSTEM_GUIDE.md) | Configuration and defaults system |
| [CHANGELOG_MISC.md](CHANGELOG_MISC.md) | Recent changes and updates |

### 📚 **Function Library Documentation** (9 libraries)

**Core Functions**:
- [build.func/](misc/build.func/) - Container creation orchestrator (7 files)
- [core.func/](misc/core.func/) - Utility functions (5 files)
- [error_handler.func/](misc/error_handler.func/) - Error handling (5 files)
- [api.func/](misc/api.func/) - Proxmox API integration (5 files)

**Installation Functions**:
- [install.func/](misc/install.func/) - Container setup (5 files)
- [tools.func/](misc/tools.func/) - Package and tool installation (6 files)

**Alpine Linux Functions**:
- [alpine-install.func/](misc/alpine-install.func/) - Alpine setup (5 files)
- [alpine-tools.func/](misc/alpine-tools.func/) - Alpine tools (5 files)

**VM Functions**:
- [cloud-init.func/](misc/cloud-init.func/) - VM provisioning (5 files)

---

## 📋 **All Documentation Files**

### Root Level (13 main files + 6 directory structures)

```
/docs/
├─ CONTRIBUTION_GUIDE.md        (2800+ lines) Contributing guide
├─ UPDATED_APP-ct.md            (900+ lines)  ct script guide
├─ UPDATED_APP-install.md       (1000+ lines) install script guide
├─ TECHNICAL_REFERENCE.md       (600+ lines)  Architecture reference
├─ DEFAULTS_SYSTEM_GUIDE.md     (700+ lines)  Configuration guide
├─ CHANGELOG_MISC.md            (450+ lines)  Change history
├─ EXIT_CODES.md                (400+ lines)  Exit codes reference
├─ DEV_MODE.md                  (400+ lines)  Dev mode guide
├─ INDEX.md                     (This file)   Documentation index
│
├─ ct/                          README for container scripts ★ NEW
├─ install/                     README for installation scripts ★ NEW
├─ vm/                          README for VM scripts ★ NEW
├─ tools/                       README for tools & utilities ★ NEW
├─ api/                         README for API integration ★ NEW
│
└─ misc/                        Function libraries (detailed below)
```

### Project Structure Mirror with Docs (48 files in misc/)

Each top-level project directory (`/ct`, `/install`, `/vm`, `/tools`, `/api`) has a documentation companion in `/docs/` with a README explaining that section.

### misc/ Subdirectories (48 files)

```
/docs/misc/
├─ README.md                    (comprehensive overview)
│
├─ build.func/                  (7 files)
│  ├─ README.md
│  ├─ BUILD_FUNC_FLOWCHART.md
│  ├─ BUILD_FUNC_ARCHITECTURE.md
│  ├─ BUILD_FUNC_ENVIRONMENT_VARIABLES.md
│  ├─ BUILD_FUNC_FUNCTIONS_REFERENCE.md
│  ├─ BUILD_FUNC_EXECUTION_FLOWS.md
│  └─ BUILD_FUNC_USAGE_EXAMPLES.md
│
├─ core.func/                   (5 files)
│  ├─ README.md
│  ├─ CORE_FLOWCHART.md
│  ├─ CORE_FUNCTIONS_REFERENCE.md
│  ├─ CORE_INTEGRATION.md
│  └─ CORE_USAGE_EXAMPLES.md
│
├─ error_handler.func/          (5 files)
│  ├─ README.md
│  ├─ ERROR_HANDLER_FLOWCHART.md
│  ├─ ERROR_HANDLER_FUNCTIONS_REFERENCE.md
│  ├─ ERROR_HANDLER_INTEGRATION.md
│  └─ ERROR_HANDLER_USAGE_EXAMPLES.md
│
├─ api.func/                    (5 files)
│  ├─ README.md
│  ├─ API_FLOWCHART.md
│  ├─ API_FUNCTIONS_REFERENCE.md
│  ├─ API_INTEGRATION.md
│  └─ API_USAGE_EXAMPLES.md
│
├─ install.func/                (5 files)
│  ├─ README.md
│  ├─ INSTALL_FUNC_FLOWCHART.md
│  ├─ INSTALL_FUNC_FUNCTIONS_REFERENCE.md
│  ├─ INSTALL_FUNC_INTEGRATION.md
│  └─ INSTALL_FUNC_USAGE_EXAMPLES.md
│
├─ tools.func/                  (6 files) ★ NEW
│  ├─ README.md
│  ├─ TOOLS_FUNC_FLOWCHART.md
│  ├─ TOOLS_FUNC_FUNCTIONS_REFERENCE.md
│  ├─ TOOLS_FUNC_INTEGRATION.md
│  ├─ TOOLS_FUNC_USAGE_EXAMPLES.md
│  └─ TOOLS_FUNC_ENVIRONMENT_VARIABLES.md
│
├─ alpine-install.func/         (5 files) ★ NEW
│  ├─ README.md
│  ├─ ALPINE_INSTALL_FUNC_FLOWCHART.md
│  ├─ ALPINE_INSTALL_FUNC_FUNCTIONS_REFERENCE.md
│  ├─ ALPINE_INSTALL_FUNC_INTEGRATION.md
│  └─ ALPINE_INSTALL_FUNC_USAGE_EXAMPLES.md
│
├─ alpine-tools.func/           (5 files) ★ NEW
│  ├─ README.md
│  ├─ ALPINE_TOOLS_FUNC_FLOWCHART.md
│  ├─ ALPINE_TOOLS_FUNC_FUNCTIONS_REFERENCE.md
│  ├─ ALPINE_TOOLS_FUNC_INTEGRATION.md
│  └─ ALPINE_TOOLS_FUNC_USAGE_EXAMPLES.md
│
└─ cloud-init.func/             (5 files) ★ NEW
   ├─ README.md
   ├─ CLOUD_INIT_FUNC_FLOWCHART.md
   ├─ CLOUD_INIT_FUNC_FUNCTIONS_REFERENCE.md
   ├─ CLOUD_INIT_FUNC_INTEGRATION.md
   └─ CLOUD_INIT_FUNC_USAGE_EXAMPLES.md
## 📊 **Documentation Statistics**

| Metric | Count |
|--------|:---:|
| Total Documentation Files | 67 |
| Project Directories Documented | 6 (ct, install, vm, tools, api, misc) |
| Function Libraries Documented | 9 |
| Total Functions Referenced | 150+ |
| Total Lines of Documentation | 15,000+ |
| Code Examples | 50+ |
| Visual Flowcharts | 15+ |

**New in this update (★ NEW)**: 6 new section directories (ct/, install/, vm/, tools/, api/) mirroring project structure
| Code Examples | 50+ |
| Visual Flowcharts | 15+ |

**New in this update (★ NEW)**: 5 new function library subdirectories with 25 files

---

## 🎓 **Learning Paths**

### Path 1: Beginner - First Time Contributing (2-3 hours)

1. Read: [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md) - Quick Start section
2. Read: [UPDATED_APP-ct.md](UPDATED_APP-ct.md) - Overview
3. Read: [UPDATED_APP-install.md](UPDATED_APP-install.md) - Overview
4. Study: One real example from each guide
5. Create your first ct/app.sh and install/app-install.sh
6. Submit PR!

### Path 2: Intermediate - Deep Understanding (4-6 hours)

1. Read: [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md)
2. Study: [misc/build.func/README.md](misc/build.func/README.md)
3. Study: [misc/tools.func/README.md](misc/tools.func/README.md)
4. Study: [misc/install.func/README.md](misc/install.func/README.md)
5. Review: EXIT_CODES and error handling
6. Create an advanced application with custom setup

### Path 3: Advanced - Architecture Mastery (8+ hours)

1. Read all TECHNICAL_REFERENCE.md
2. Study all 9 function libraries in depth:
   - Flowchart
   - Functions Reference
   - Integration Guide
   - Usage Examples
3. Review: [CHANGELOG_MISC.md](CHANGELOG_MISC.md) for recent changes
4. Review: [DEFAULTS_SYSTEM_GUIDE.md](DEFAULTS_SYSTEM_GUIDE.md)
5. Study: [DEV_MODE.md](DEV_MODE.md) for debugging
6. Contribute to function libraries or complex applications

### Path 4: Operator/User - Configuration Focus (1-2 hours)

1. Read: [DEFAULTS_SYSTEM_GUIDE.md](DEFAULTS_SYSTEM_GUIDE.md)
2. Read: [EXIT_CODES.md](EXIT_CODES.md) - for troubleshooting
3. Read: [DEV_MODE.md](DEV_MODE.md) - for debugging

---

## 🔍 **Search Guide**

### Looking for...

**How do I create a ct script?**
→ [UPDATED_APP-ct.md](UPDATED_APP-ct.md)

**How do I create an install script?**
→ [UPDATED_APP-install.md](UPDATED_APP-install.md)

**What does exit code 206 mean?**
→ [EXIT_CODES.md](EXIT_CODES.md#container-creation-errors-200-209)

**How do I debug a failed installation?**
→ [DEV_MODE.md](DEV_MODE.md)

**What are the default configuration options?**
→ [DEFAULTS_SYSTEM_GUIDE.md](DEFAULTS_SYSTEM_GUIDE.md)

**What's a function in build.func?**
→ [misc/build.func/BUILD_FUNC_FUNCTIONS_REFERENCE.md](misc/build.func/BUILD_FUNC_FUNCTIONS_REFERENCE.md)

**How do I install Node.js in a container?**
→ [misc/tools.func/TOOLS_FUNC_FUNCTIONS_REFERENCE.md](misc/tools.func/TOOLS_FUNC_FUNCTIONS_REFERENCE.md#setup_nodejsversion)

**How do Alpine containers differ from Debian?**
→ [misc/alpine-install.func/README.md](misc/alpine-install.func/README.md)

**What changed recently in /misc?**
→ [CHANGELOG_MISC.md](CHANGELOG_MISC.md)

---

## ✅ **Documentation Completeness**

- ✅ All 9 function libraries have dedicated subdirectories
- ✅ Each library has 5-6 detailed documentation files
- ✅ Complete flowcharts for complex processes
- ✅ Alphabetical function references with signatures
- ✅ Real-world usage examples for every pattern
- ✅ Integration guides showing component relationships
- ✅ Best practices documented with DO/DON'T sections
- ✅ Troubleshooting guides for common issues
- ✅ Exit codes fully mapped and explained
- ✅ Architecture documentation with diagrams

---

## 🚀 **Standardized Documentation Pattern**

Each function library follows this consistent pattern:

```
function-library/
├─ README.md                              # Quick reference
├─ FUNCTION_LIBRARY_FLOWCHART.md          # Visual flows
├─ FUNCTION_LIBRARY_FUNCTIONS_REFERENCE.md # Complete reference
├─ FUNCTION_LIBRARY_INTEGRATION.md        # How it connects
├─ FUNCTION_LIBRARY_USAGE_EXAMPLES.md     # Real examples
└─ [FUNCTION_LIBRARY_ENVIRONMENT_VARIABLES.md]  # (if needed)
```

This makes it easy to:
- Find information quickly
- Navigate between related docs
- Understand component relationships
- Learn from examples
- Reference complete function signatures

---

## 📝 **Last Updated**

- **Date**: December 2025
- **Version**: 2.0 (Comprehensive Restructure)
- **Status**: ✅ All 9 function libraries fully documented and standardized
- **New This Update**: tools.func/, alpine-install.func/, alpine-tools.func/, cloud-init.func/ subdirectories with complete documentation

---

## 🤝 **Contributing Documentation**

Found an error or want to improve documentation?

1. Open an issue: https://github.com/community-scripts/ProxmoxVED/issues
2. Or submit a PR improving documentation
3. See: [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md) for details

---

## 📚 **Related Resources**

- **GitHub Repository**: https://github.com/community-scripts/ProxmoxVED
- **Proxmox Documentation**: https://pve.proxmox.com/wiki/
- **Community Discussions**: https://github.com/community-scripts/ProxmoxVED/discussions

---

**Ready to get started?** Choose a learning path above or use the quick navigation. 🚀
