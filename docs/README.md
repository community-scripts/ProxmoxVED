# 📚 ProxmoxVED Documentation

Complete documentation for the ProxmoxVED project - mirroring the project structure with comprehensive guides for every component.

---

## 🎯 **Quick Start by Role**

### 👤 **I'm a...**

**New Contributor**
→ Start: [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md)
→ Then: Choose your path below

**Container Creator**
→ Read: [ct/README.md](ct/README.md)
→ Guide: [UPDATED_APP-ct.md](UPDATED_APP-ct.md)
→ Reference: [misc/build.func/](misc/build.func/)

**Installation Script Developer**
→ Read: [install/README.md](install/README.md)
→ Guide: [UPDATED_APP-install.md](UPDATED_APP-install.md)
→ Reference: [misc/tools.func/](misc/tools.func/)

**VM Provisioner**
→ Read: [vm/README.md](vm/README.md)
→ Reference: [misc/cloud-init.func/](misc/cloud-init.func/)

**Tools Developer**
→ Read: [tools/README.md](tools/README.md)
→ Reference: [misc/build.func/](misc/build.func/)

**API Integrator**
→ Read: [api/README.md](api/README.md)
→ Reference: [misc/api.func/](misc/api.func/)

**System Operator**
→ Start: [EXIT_CODES.md](EXIT_CODES.md)
→ Then: [DEFAULTS_SYSTEM_GUIDE.md](DEFAULTS_SYSTEM_GUIDE.md)
→ Debug: [DEV_MODE.md](DEV_MODE.md)

**Architect**
→ Read: [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md)
→ Deep Dive: [misc/README.md](misc/README.md)

---

## 📁 **Documentation Structure**

### Project-Mirrored Directories

Each major project directory has documentation:

```
ProxmoxVED/
├─ ct/                 ↔ docs/ct/README.md
├─ install/           ↔ docs/install/README.md
├─ vm/                ↔ docs/vm/README.md
├─ tools/            ↔ docs/tools/README.md
├─ api/              ↔ docs/api/README.md
└─ misc/             ↔ docs/misc/ (9 function libraries)
```

### Core Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md) | How to contribute | Contributors |
| [UPDATED_APP-ct.md](UPDATED_APP-ct.md) | Create ct scripts | Container developers |
| [UPDATED_APP-install.md](UPDATED_APP-install.md) | Create install scripts | Installation developers |
| [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md) | Architecture deep-dive | Architects, advanced users |
| [DEFAULTS_SYSTEM_GUIDE.md](DEFAULTS_SYSTEM_GUIDE.md) | Configuration system | Operators, power users |
| [EXIT_CODES.md](EXIT_CODES.md) | Exit code reference | Troubleshooters |
| [DEV_MODE.md](DEV_MODE.md) | Debugging tools | Developers |
| [CHANGELOG_MISC.md](CHANGELOG_MISC.md) | Recent changes | Everyone |

---

## 📂 **Directory Guide**

### [ct/](ct/) - Container Scripts
Documentation for `/ct` - Container creation scripts that run on the Proxmox host.

**Includes**:
- Overview of container creation process
- Link to [UPDATED_APP-ct.md](UPDATED_APP-ct.md) guide
- Reference to [misc/build.func/](misc/build.func/)
- Quick start for creating new containers

### [install/](install/) - Installation Scripts
Documentation for `/install` - Scripts that run inside containers to install applications.

**Includes**:
- Overview of 10-phase installation pattern
- Link to [UPDATED_APP-install.md](UPDATED_APP-install.md) guide
- Reference to [misc/tools.func/](misc/tools.func/)
- Alpine vs Debian differences

### [vm/](vm/) - Virtual Machine Scripts
Documentation for `/vm` - VM creation scripts using cloud-init provisioning.

**Includes**:
- Overview of VM provisioning
- Link to [misc/cloud-init.func/](misc/cloud-init.func/)
- VM vs Container comparison
- Cloud-init examples

### [tools/](tools/) - Tools & Utilities
Documentation for `/tools` - Management tools and add-ons.

**Includes**:
- Overview of tools structure
- Integration points
- Contributing new tools
- Common operations

### [api/](api/) - API Integration
Documentation for `/api` - Telemetry and API backend.

**Includes**:
- API overview
- Integration methods
- API endpoints
- Privacy information

### [misc/](misc/) - Function Libraries
Documentation for `/misc` - 9 core function libraries with complete references.

**Contains**:
- **build.func/** - Container orchestration (7 files)
- **core.func/** - Utilities and messaging (5 files)
- **error_handler.func/** - Error handling (5 files)
- **api.func/** - API integration (5 files)
- **install.func/** - Container setup (5 files)
- **tools.func/** - Package installation (6 files)
- **alpine-install.func/** - Alpine setup (5 files)
- **alpine-tools.func/** - Alpine tools (5 files)
- **cloud-init.func/** - VM provisioning (5 files)

---

## 🎓 **Learning Paths**

### Path 1: First-Time Contributor (2-3 hours)

1. [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md) - Quick Start
2. Pick your area:
   - Containers → [ct/README.md](ct/README.md)
   - Installation → [install/README.md](install/README.md)
   - VMs → [vm/README.md](vm/README.md)
3. Read the corresponding UPDATED_APP guide
4. Study existing similar script
5. Create your contribution
6. Submit PR

### Path 2: Intermediate Developer (4-6 hours)

1. [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md)
2. Dive into function libraries:
   - [misc/build.func/README.md](misc/build.func/README.md)
   - [misc/tools.func/README.md](misc/tools.func/README.md)
   - [misc/install.func/README.md](misc/install.func/README.md)
3. Study advanced examples
4. Create complex applications
5. Review [CHANGELOG_MISC.md](CHANGELOG_MISC.md) for recent changes

### Path 3: Advanced Architect (8+ hours)

1. All of Intermediate Path
2. Study all 9 function libraries:
   - Each with FLOWCHART, FUNCTIONS_REFERENCE, INTEGRATION, USAGE_EXAMPLES
3. [DEFAULTS_SYSTEM_GUIDE.md](DEFAULTS_SYSTEM_GUIDE.md) - Configuration system
4. [DEV_MODE.md](DEV_MODE.md) - Debugging and development
5. Design new features or function libraries

### Path 4: Troubleshooter (30 minutes - 1 hour)

1. [EXIT_CODES.md](EXIT_CODES.md) - Find error code
2. [DEV_MODE.md](DEV_MODE.md) - Run with debugging
3. Check relevant function library docs
4. Review logs and fix

---

## 📊 **By the Numbers**

| Metric | Count |
|--------|:---:|
| **Documentation Files** | 67 |
| **Total Lines** | 15,000+ |
| **Function Libraries** | 9 |
| **Functions Documented** | 150+ |
| **Code Examples** | 50+ |
| **Flowcharts** | 15+ |
| **Do/Don't Sections** | 20+ |
| **Real-World Examples** | 30+ |

---

## 🔍 **Find It Fast**

### By Feature
- **How do I create a container?** → [UPDATED_APP-ct.md](UPDATED_APP-ct.md)
- **How do I create an install script?** → [UPDATED_APP-install.md](UPDATED_APP-install.md)
- **How do I create a VM?** → [vm/README.md](vm/README.md)
- **How do I install Node.js?** → [misc/tools.func/](misc/tools.func/)
- **How do I debug?** → [DEV_MODE.md](DEV_MODE.md)

### By Error
- **Exit code 206?** → [EXIT_CODES.md](EXIT_CODES.md)
- **Network failed?** → [misc/install.func/](misc/install.func/)
- **Package error?** → [misc/tools.func/](misc/tools.func/)

### By Role
- **Contributor** → [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md)
- **Operator** → [DEFAULTS_SYSTEM_GUIDE.md](DEFAULTS_SYSTEM_GUIDE.md)
- **Developer** → [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md)
- **Architect** → [misc/README.md](misc/README.md)

---

## ✅ **Documentation Features**

- ✅ **Project-mirrored structure** - Organized like the actual project
- ✅ **Complete function references** - Every function documented
- ✅ **Real-world examples** - Copy-paste ready code
- ✅ **Visual flowcharts** - ASCII diagrams of workflows
- ✅ **Integration guides** - How components connect
- ✅ **Troubleshooting** - Common issues and solutions
- ✅ **Best practices** - DO/DON'T sections throughout
- ✅ **Learning paths** - Structured curriculum by role
- ✅ **Quick references** - Fast lookup by error code
- ✅ **Comprehensive index** → [INDEX.md](INDEX.md)

---

## 🚀 **Start Here**

**New to ProxmoxVED?** → [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md)

**Looking for something specific?** → [INDEX.md](INDEX.md)

**Need to debug?** → [EXIT_CODES.md](EXIT_CODES.md)

**Want to understand architecture?** → [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md)

---

## 🤝 **Contributing Documentation**

Found an error? Want to improve docs?

1. Open issue: https://github.com/community-scripts/ProxmoxVED/issues
2. Or submit PR with improvements
3. See [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md) for details

---

## 📝 **Status**

- **Last Updated**: December 2025
- **Version**: 2.1 (Project Structure Mirror)
- **Completeness**: ✅ 100% - All components documented
- **Quality**: ✅ Production-ready
- **Examples**: ✅ 50+ tested examples

---

**Welcome to ProxmoxVED! Start with [CONTRIBUTION_GUIDE.md](CONTRIBUTION_GUIDE.md) or choose your role above.** 🚀
