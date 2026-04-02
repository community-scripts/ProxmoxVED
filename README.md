# ioquake3-LXC: Automated Quake 3 Server for Proxmox

This script provides a streamlined, automated way to deploy a **Debian-based ioquake3 server** within a Proxmox LXC container. It handles dependencies, compilation, and setup with minimal user intervention.

---

## Overview

Unlike traditional manual setups, this installer automates the container creation and the compilation of a fresh copy of **ioquake3**. It is designed to be user-friendly, handling internal Container IDs and file permissions automatically.

### Key Improvements in this Fork:
* **One-Command Setup:** No more copy-pasting `curl | pct exec` lines; everything is handled internally.
* **Automatic Detection:** The script waits for game files and handles deployment once they are present.
* **No Manual CTIDs:** No need to hunt for your Container ID for `pct push` or `chown` tasks.
* **Streamlined Asset Upload:** Leverages an ISO-extension workaround to bypass Proxmox Web UI upload restrictions, eliminating the need for manual SFTP/CLI transfers.

---

## 1. Preparation

Due to legal requirements, this script **does not** include proprietary game data. You must provide your own retail assets.

1.  Locate your `pak0.pk3` file from your original Quake 3 Arena CD or Steam installation.
2.  **Important:** Rename `pak0.pk3` to **`pak0.iso`**.
> [!TIP]
> This allows you to upload the file directly via the Proxmox Web UI without encountering "Unsupported File Extension" errors.

---

## 2. Installation

Run the following command in your **Proxmox Host Shell**:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/geedoes/ProxmoxVED/refs/heads/main/ct/ioquake3.sh)"
```
---

## 3. Deployment & Asset Upload

The script will automate the LXC creation and then **pause** to wait for your game files.

1.  **Open Proxmox Web UI** in your browser.
2.  **Navigate to:** `Datacenter` → `(Your Node)` → `local` storage.
3.  **Select the ISO Images** tab on the left sidebar.
4.  **Click Upload** and select your renamed **`pak0.iso`**.
5.  **Wait:** Once the Proxmox "Task Viewer" says **OK**, the script will automatically:
    * **Detect** the file in your storage.
    * **Move** it into the LXC container.
    * **Rename** it back to `.pk3` for the game engine.
    * **Start** your Quake 3 server.
