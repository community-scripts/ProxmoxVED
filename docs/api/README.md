# API Integration Documentation

## Overview

The telemetry and diagnostics API uses **PocketBase** as backend, hosted at `http://db.community-scripts.org`. All telemetry data is stored in the `_dev_telemetry_data` collection.

The Go/MongoDB API server (`/api` directory) has been replaced entirely by PocketBase.

## Key Components

### PocketBase Backend
- **URL**: `http://db.community-scripts.org`
- **Collection**: `_dev_telemetry_data`
- **Admin UI**: `http://db.community-scripts.org/_/#/collections`
- RESTful API for receiving telemetry data
- Installation statistics tracking
- Error reporting and analytics

### Integration with Scripts
The API is integrated into all installation scripts via `api.func`:
- Sends installation start/completion events
- Reports errors and exit codes with numeric values
- Collects anonymous usage statistics
- Enables project analytics

## Documentation Structure

- **[misc/api.func/](../misc/api.func/)** - API function library documentation
- **[misc/api.func/README.md](../misc/api.func/README.md)** - Quick reference
- **[misc/api.func/API_FUNCTIONS_REFERENCE.md](../misc/api.func/API_FUNCTIONS_REFERENCE.md)** - Complete function reference

## API Functions

The `api.func` library provides:

### `post_to_api()`
Send LXC container installation data to PocketBase.

Creates a new record in `_dev_telemetry_data` with status `installing`.

### `post_to_api_vm()`
Send VM installation data to PocketBase.

Creates a new record with `type=vm` and `ct_type=2`.

### `post_update_to_api(status, exit_code)`
Update installation status via PocketBase PATCH.

Maps status values:
- `"done"` → PocketBase status `"sucess"`
- `"failed"` → PocketBase status `"failed"`

### `explain_exit_code(code)`
Get human-readable error description from exit code.

**Usage**:
```bash
ERROR_DESC=$(explain_exit_code 137)
# → "Killed (SIGKILL / Out of memory?)"
```

## PocketBase Collection Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | text (auto) | yes | PocketBase record ID |
| `random_id` | text | yes | Session UUID (unique) |
| `type` | select | yes | `lxc`, `vm`, `addon`, `pve` |
| `ct_type` | number | yes | 1=LXC, 2=VM |
| `nsapp` | text | yes | Application name |
| `status` | select | yes | `installing`, `sucess`, `failed`, `unknown` |
| `disk_size` | number | no | Disk size in GB |
| `core_count` | number | no | CPU cores |
| `ram_size` | number | no | RAM in MB |
| `os_type` | text | no | OS type (debian, ubuntu, etc.) |
| `os_version` | text | no | OS version |
| `pve_version` | text | no | Proxmox VE version |
| `method` | text | no | Installation method |
| `error` | text | no | Error description |
| `exit_code` | number | no | Numeric exit code |
| `created` | autodate | auto | Record creation timestamp |
| `updated` | autodate | auto | Last update timestamp |

## API Endpoints (PocketBase REST)

**Base URL**: `http://db.community-scripts.org`

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/collections/_dev_telemetry_data/records` | Create telemetry record |
| `PATCH` | `/api/collections/_dev_telemetry_data/records/{id}` | Update record status |
| `GET` | `/api/collections/_dev_telemetry_data/records` | List/search records |

### Query Parameters (GET)
- `filter` – PocketBase filter syntax, e.g. `(nsapp='debian' && status='failed')`
- `sort` – Sort fields, e.g. `-created,nsapp`
- `page` / `perPage` – Pagination
- `fields` – Limit returned fields

## API Integration Points

### In Container Creation (`ct/AppName.sh`)
- Called by `build.func` to report container creation via `post_to_api`
- Sends initial container setup data with status `installing`
- Reports success or failure via `post_update_to_api`

### In VM Creation (`vm/AppName.sh`)
- Calls `post_to_api_vm` after VM creation
- Status updates via `post_update_to_api`

### Data Flow
```
Installation Scripts
    │
    ├─ Call: api.func functions
    │
    ├─ POST → PocketBase (create record, status=installing)
    │           └─ Returns record ID (stored in PB_RECORD_ID)
    │
    └─ PATCH → PocketBase (update record with final status)
                └─ status=sucess/failed + exit_code + error
```

## Privacy

All API data:
- ✅ Anonymous (no personal data)
- ✅ Aggregated for statistics
- ✅ Used only for project improvement
- ✅ No tracking of user identities
- ✅ Can be disabled via diagnostics settings

## Debugging API Issues

If API calls fail:
1. Check internet connectivity
2. Verify PocketBase endpoint: `curl -s http://db.community-scripts.org/api/health`
3. Review error codes in [EXIT_CODES.md](../EXIT_CODES.md)
4. Check that `DIAGNOSTICS=yes` in `/usr/local/community-scripts/diagnostics`
5. Report issues on [GitHub](https://git.community-scripts.org/community-scripts/ProxmoxVED/issues)

---

**Last Updated**: February 2026
**Maintainers**: community-scripts team
