# 📚 Proxmox VE Community Scripts Documentation

Official documentation for using, understanding, developing, and contributing to the Proxmox VE Community Scripts project.

> [!IMPORTANT]
> The latest documentation is always published on our website:
>
> **https://community-scripts.org/docs**
>
> The website is the canonical documentation source. Repository files may represent source content or implementation details, but the published documentation should always be used as the current reference.

---

## 🚀 Start Here

Choose the area that best matches what you want to do:

| Goal                                         | Documentation                                                                 |
| -------------------------------------------- | ----------------------------------------------------------------------------- |
| Create or understand LXC container scripts   | [Container Scripts](https://community-scripts.org/docs/ct/readme)             |
| Develop installation scripts                 | [Installation Scripts](https://community-scripts.org/docs/install/readme)     |
| Create or understand virtual machine scripts | [VM Scripts](https://community-scripts.org/docs/vm/readme)                    |
| Configure deployments and defaults           | [Configuration Guides](https://community-scripts.org/docs/guides/readme)      |
| Use management tools and add-ons             | [Tools & Add-ons](https://community-scripts.org/docs/tools/readme)            |
| Contribute scripts or project changes        | [Contribution Guide](https://community-scripts.org/docs/contribution/readme)  |
| Understand shared Bash libraries             | [Function Libraries](https://community-scripts.org/docs/misc/readme)          |
| Understand API and telemetry integration     | [API Integration](https://community-scripts.org/docs/api/readme)              |
| Study the internal architecture              | [Technical Reference](https://community-scripts.org/docs/technical_reference) |
| Troubleshoot an error                        | [Exit Codes Reference](https://community-scripts.org/docs/exit_codes)         |
| Enable development and debugging features    | [Development Mode Guide](https://community-scripts.org/docs/dev_mode)         |

---

## 📖 Documentation Areas

### Container Scripts

Documentation for host-side scripts in `ct/` that create and configure Proxmox LXC containers.

Topics include:

* Container creation flow
* Script structure and conventions
* Default and advanced settings
* Integration with `build.func`
* Container and installation script interaction
* Templates and practical examples

➡️ [Open Container Scripts Documentation](https://community-scripts.org/docs/ct/readme)

---

### Installation Scripts

Documentation for scripts in `install/` that run inside containers and install applications.

Topics include:

* Installation workflow and setup phases
* Debian, Ubuntu, and Alpine patterns
* Runtime and database installation
* Application deployment
* Configuration and service creation
* Update and migration logic
* Integration with helper functions

➡️ [Open Installation Scripts Documentation](https://community-scripts.org/docs/install/readme)

---

### VM Scripts

Documentation for scripts in `vm/` that create QEMU/KVM virtual machines.

Topics include:

* VM provisioning
* Cloud-init workflows
* Image handling
* Storage and disk configuration
* Network configuration
* VM-specific contribution guidance

➡️ [Open VM Scripts Documentation](https://community-scripts.org/docs/vm/readme)

---

### Configuration Guides

Guides for configuring and automating Community Scripts deployments.

Topics include:

* Configuration variables
* Default settings
* Per-script overrides
* Storage and network configuration
* Unattended deployments
* Environment-variable-based provisioning
* [Incus host setup](guides/incus.md) (unified `ct/` scripts on Incus)
* [Script origin (fork/branch)](guides/source-origin.md) (local checkout + remote `run.sh`)

➡️ [Open Configuration Guides](https://community-scripts.org/docs/guides/readme)

---

### Tools & Add-ons

Documentation for Proxmox VE management utilities, administration helpers, and optional add-ons.

➡️ [Open Tools & Add-ons Documentation](https://community-scripts.org/docs/tools/readme)

---

### Function Libraries

Technical documentation for the shared Bash libraries under `misc/`.

The documented libraries include:

* `build.func`
* `core.func`
* `error_handler.func`
* `api.func`
* `install.func`
* `tools.func`
* `alpine-install.func`
* `alpine-tools.func`
* `cloud-init.func`

The documentation explains individual functions, dependencies between libraries, execution flows, error handling, telemetry, logging, package management, and provisioning behavior.

➡️ [Open Function Libraries Documentation](https://community-scripts.org/docs/misc/readme)

---

### API Integration

Documentation for the website API, telemetry services, diagnostics, metadata handling, and related integration points.

➡️ [Open API Documentation](https://community-scripts.org/docs/api/readme)

---

## 🤝 Contributing

The contribution documentation contains the current requirements, templates, coding standards, and review guidance for submitting changes.

### Main resources

* [Contribution Overview](https://community-scripts.org/docs/contribution/readme)
* [Contribution Guide](https://community-scripts.org/docs/contribution/contributing)
* [Script Templates](https://community-scripts.org/docs/contribution/templates_ct/appname)
* [AI Coding Agent Guidelines](https://community-scripts.org/docs/contribution/agents)

Before submitting a pull request:

1. Read the current contribution guide.
2. Review the relevant script documentation.
3. Start from an official template where available.
4. Compare your implementation with similar existing scripts.
5. Test the complete creation, installation, update, and error-handling flow.

---

## 🛠 Troubleshooting

For failed installations or unexpected behavior, start with:

1. [Exit Codes Reference](https://community-scripts.org/docs/exit_codes)
2. [Development Mode Guide](https://community-scripts.org/docs/dev_mode)
3. [Function Libraries](https://community-scripts.org/docs/misc/readme)
4. The documentation for the affected script type

When reporting an issue, include:

* Proxmox VE version
* Script name
* Exact command used
* Complete error output
* Exit code
* Relevant debug or verbose logs
* Whether default or advanced settings were used

---

## 🏗 Technical Reference

Advanced implementation details are documented separately:

* [Technical Reference](https://community-scripts.org/docs/technical_reference)
* [Function Libraries](https://community-scripts.org/docs/misc/readme)
* [API Integration](https://community-scripts.org/docs/api/readme)
* [Development Mode](https://community-scripts.org/docs/dev_mode)
* [Exit Codes](https://community-scripts.org/docs/exit_codes)

These sections cover architecture, configuration precedence, execution flow, helper-library relationships, telemetry, error handling, and development internals.

---

## 🔍 Search the Documentation

The documentation website provides full-text search.

Open:

**https://community-scripts.org/docs**

Then use the search field or press:

* `Ctrl + K` on Windows and Linux
* `⌘ + K` on macOS

---

## 📝 Documentation Updates

Documentation is maintained continuously and published through the central documentation website.

Do not rely on hard-coded document counts, line counts, version labels, completeness percentages, or last-updated dates in this README. These values become outdated quickly and do not represent the current state of the published documentation.

For the latest content, navigation, examples, and references, always use:

## **https://community-scripts.org/docs**

---

## 💬 Support and Feedback

Found an error or missing information?

* [Open a GitHub issue](https://github.com/community-scripts/ProxmoxVE/issues)
* Submit a pull request with documentation improvements
* Join the [Community Scripts Discord](https://discord.gg/UHrpNWGwkH)

---

**Proxmox VE Community Scripts Documentation**

[Open Documentation](https://community-scripts.org/docs) · [View Scripts](https://community-scripts.org) · [Contribute](https://community-scripts.org/docs/contribution/readme)
