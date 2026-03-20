## 🤖 PocketBase Bot — Command Reference

> Available to **org members only** (Contributors team).
> Trigger by posting a comment on any Issue or PR.

---

### 🔧 Field Updates
Simple key=value pairs. Multiple in one line.
```
/pocketbase <slug> field=value [field=value ...]
```
**Boolean fields** (`true`/`false`): `updateable` `privileged` `has_arm` `is_dev` `is_disabled` `is_deleted`
**Text fields**: `name` `description` `logo` `documentation` `website` `project_url` `github` `config_path` `disable_message` `deleted_message`
**Number**: `port`
**Nullable**: `default_user` `default_passwd` *(empty value = null: `default_passwd=`)*

**Examples:**
```
/pocketbase homeassistant is_disabled=true disable_message="Broken upstream"
/pocketbase homeassistant documentation=https://www.home-assistant.io/docs
/pocketbase homeassistant is_dev=false
/pocketbase homeassistant default_passwd=
```

---

### 📝 set — HTML / Multiline / Special Characters
Use a code block for values that contain HTML, links, quotes or newlines.
````
/pocketbase <slug> set <field>
```
Your content here — HTML tags, links, quotes, all fine
```
````
**Allowed fields:** `name` `description` `logo` `documentation` `website` `project_url` `github` `config_path` `disable_message` `deleted_message`

---

### 🗒️ Notes
```
/pocketbase <slug> note list
/pocketbase <slug> note add <type> "<text>"
/pocketbase <slug> note edit <type> "<old text>" "<new text>"
/pocketbase <slug> note remove <type> "<text>"
```
Note types come from `z_ref_note_types` in PocketBase (e.g. `info`, `warning`).
If text doesn't match exactly, the bot lists all current notes automatically.

---

### ⚙️ Install Method Resources
```
/pocketbase <slug> method list
/pocketbase <slug> method <type> hdd=10
/pocketbase <slug> method <type> cpu=4 ram=2048 hdd=20
```
`<type>` matches the install method type name (e.g. `default`, `alpine`). Use `method list` to see available types and current values. `ram` = MB, `hdd` = GB.

---

### 💡 Tips
- The bot reacts with 👀 when it picks up the command, ✅ on success, 👎 on error
- On any error, a comment explains what went wrong
- `note edit` / `note remove` show the current note list if the text doesn't match
