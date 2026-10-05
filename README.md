# 🚧 DevScripts (Development Repository)

**Warning: Scripts in this repository are still being developed and tested. Do not use them in production.**

---

## 🔧 What is this?

DevScripts is where new community-scripts are built and tested before they are released to [ProxmoxVE](https://github.com/community-scripts/ProxmoxVE). It takes every kind of script, whatever platform it targets:

| Folder | What it is | Runs on |
| --- | --- | --- |
| `ct/` + `install/` | Application containers | Proxmox VE (LXC) and Incus |
| `vm/` | Virtual machines | Proxmox VE |
| `tools/addon/` | Add-ons for an existing container or VM | Inside the guest |
| `tools/pve/` | Host tools | Proxmox VE, Backup Server, Mail Gateway, Datacenter Manager |

One application script creates its container on Proxmox VE and on Incus alike; the engine in [core](https://github.com/community-scripts/core) handles the platform. Once a script has passed testing it moves to ProxmoxVE, and the [Incus](https://github.com/community-scripts/Incus) repository picks up application scripts from there.

This repository was called ProxmoxVED before.

---

## 🧪 Testing a script

Scripts under test have an issue here and a thread on Discord with the exact command to run. Containers created from this repository show a development banner on login, with a link to their testing thread where there is one.

Report back in that thread: works, broken, or anything odd — one line is enough. Without feedback a script cannot be released.

---

## 🛠️ Contributing

New scripts start here, not in ProxmoxVE. The [documentation](https://community-scripts.org/docs) explains how to write one; open the pull request against this repository and fill in the template.

---

## 💬 Get Involved

- **Discord**: [Join the community-scripts Discord server](https://discord.gg/3AnUqsXnmK)
- **GitHub Issues**: [Report problems with a script under test](https://github.com/community-scripts/DevScripts/issues)
- **Script requests**: [ProxmoxVE Discussions](https://github.com/community-scripts/ProxmoxVE/discussions/new?category=request-script)

## 📜 License

This project is licensed under the [MIT License](LICENSE). It was originally created by [tteck](https://github.com/tteck) and is now community-driven.

</br>
</br>
<p align="center">
  <i style="font-size: smaller;"><b>Proxmox</b>® is a registered trademark of <a href="https://www.proxmox.com/en/about/company">Proxmox Server Solutions GmbH</a>.</i>
</p>
