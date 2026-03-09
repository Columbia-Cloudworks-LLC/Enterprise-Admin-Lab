# Enterprise Admin Lab

PowerShell-based toolset for defining, spinning up, and tearing down Hyper-V Active Directory lab environments on a Windows 11 Pro host. Lab topology is driven entirely by JSON configuration — no hard-coded server names, IP ranges, or roles.

**Current status:** Hybrid provisioning is implemented. `-Create` now handles Hyper-V resources, unattended install artifacts, first-boot guest baseline, domain sequencing (DC-first), and optional Ansible post-provision orchestration.

---

## Prerequisites

- Windows 11 Pro with Hyper-V feature enabled
- PowerShell 5.1+ or PowerShell 7
- Local administrator rights
- Node.js 20 LTS — [nodejs.org](https://nodejs.org/)
- 16 GB RAM (recommended minimum for lab VMs)
- Windows Server / client VHDX base images on local storage

---

## Quick Start

```powershell
# Clone or download this repository, then from the enterprise-admin-lab directory:

# 1. Install Node.js dependencies (first run only)
cd Web
npm install
cd ..

# 2. Launch the web UI
.\Invoke-EALab.ps1

# 3. Check system prerequisites
.\Invoke-EALab.ps1 -Validate

# 4. List configured labs
.\Invoke-EALab.ps1 -List
```

The web UI opens at `http://localhost:47173` in your default browser.

---

## Entry Point

All operations go through `Invoke-EALab.ps1`:

| Switch | Description |
|---|---|
| *(default / `-OpenWebUI`)* | Start Node.js + React web app and open browser |
| `-Validate` | Run prerequisite checks (Hyper-V, RAM, disk, modules) |
| `-List` | List lab JSON configs in `Labs/` |
| `-Create -LabName <name>` | Provision Hyper-V and guest/domain orchestration |
| `-Destroy -LabName <name>` | Remove lab VM resources |
| `-Status -LabName <name>` | Return lifecycle + per-VM orchestration progress |
| `-ConfigPath <path>` | Override the default `Labs/` directory |

---

## Architecture

```
enterprise-admin-lab/
├── Invoke-EALab.ps1            # Single entry point
├── PRD.md                      # Full product requirements document
├── Config/
│   ├── defaults.json           # Global defaults (VM paths, hardware specs, domain)
│   └── lab-schema.json         # JSON Schema for validating lab configs
├── Labs/
│   └── templates/
│       └── basic-ad-lab.json   # Starter template
├── Modules/
│   ├── EALabConfig/            # JSON config CRUD (read/write/delete labs + defaults)
│   └── EALabPrerequisites/     # System validation (Hyper-V, RAM, disk, modules)
│   ├── EALabProvisioning/      # Hyper-V create/destroy/status lifecycle + orchestration
│   ├── EALabCredentials/       # Credential reference resolution (Credential Manager/prompt)
│   ├── EALabUnattend/          # Per-VM unattend generation and install media wiring
│   └── EALabGuestOrchestration/# Guest baseline, DC promotion, domain join sequencing
└── Web/                        # Node.js + React web app
    ├── README.md               # Web app setup, API reference, troubleshooting
    ├── package.json
    ├── server/                 # Express API (port 47001)
    │   └── routes/
    │       ├── labs.js         # GET/POST/PUT/DELETE /api/labs
    │       ├── defaults.js     # GET /api/defaults
    │       ├── schema.js       # GET /api/schema
    │       └── prerequisites.js # POST /api/prerequisites
    └── client/                 # Vite + React (port 47173)
        └── src/
            └── components/
                ├── LabConfigForm/    # Multi-tab form (Domain, Networks, Storage)
                └── PrerequisitesPanel.jsx
```

---

## Lab Configuration

Labs are stored as JSON files in `Labs/`. The schema is defined in `Config/lab-schema.json`.

**Minimal lab config example:**

```json
{
  "metadata": {
    "name": "gpo-test-01",
    "displayName": "GPO Test Lab 01",
    "version": "1.0"
  },
  "domain": {
    "fqdn": "lab.local",
    "netbiosName": "LAB"
  },
  "networks": [
    {
      "name": "LabInternal",
      "switchType": "Internal",
      "subnet": "192.168.10.0/24"
    }
  ],
  "vms": [
    {
      "name": "DC01",
      "role": "DomainController",
      "cpu": 2,
      "ramMB": 2048,
      "diskGB": 60,
      "generation": 2,
      "osImage": "E:\\BaseImages\\WS2022.vhdx",
      "network": "LabInternal"
    }
  ]
}
```

**Global defaults** (`Config/defaults.json`) now include guest orchestration defaults (`guestDefaults`) and default credential references (`defaultCredentials`) in addition to VM/storage/image defaults.

### Credential references

- Lab configs should store credential reference keys under `credentials` (for example `localAdminRef`, `domainAdminRef`, `dsrmRef`), not plaintext passwords.
- During `-Create`, the engine resolves references from Windows Credential Manager when available.
- If a reference is not found, it falls back to `Get-Credential` interactive prompts.

---

## Prerequisite Checks

`.\Invoke-EALab.ps1 -Validate` (or the Prerequisites tab in the web UI) checks:

| Check | Category | Requirement |
|---|---|---|
| Administrator elevation | System | Required |
| Windows version | System | Windows 10 1903+ / Server 2016+ |
| Hyper-V feature | Hyper-V | Must be enabled |
| Available RAM | System | ≥ 16 GB recommended |
| Disk space | Storage | ≥ 100 GB free recommended |
| PowerShell modules | Modules | `Hyper-V` module available |
| Virtual switch | Hyper-V | At least one Hyper-V adapter configured |

Each check returns `Passed`, `Warning`, or `Failed` with a remediation hint.

---

## Modules

### EALabConfig

Manages JSON configs in `Labs/` and `Config/`:

```powershell
Import-Module .\Modules\EALabConfig\EALabConfig.psd1

Get-EALabConfigs              # List all labs (name, displayName, vmCount, lastModified)
Get-EALabConfig -Name 'gpo-test-01'   # Read a specific lab config
Set-EALabConfig -Name 'gpo-test-01' -Config $labObject  # Write/update
Remove-EALabConfig -Name 'gpo-test-01'                  # Delete
Get-EALabDefaults             # Read global defaults
```

### EALabPrerequisites

```powershell
Import-Module .\Modules\EALabPrerequisites\EALabPrerequisites.psd1

$results = Test-EALabPrerequisites
$results | Format-Table Name, Category, Status, Message -AutoSize

Get-EALabPrerequisiteSummary  # Returns pass/warn/fail counts
```

---

## Web UI

The web app is the primary interface for lab configuration. See [`Web/README.md`](Web/README.md) for:

- Development server setup
- Production build instructions
- Full API endpoint reference
- Validation rules
- Troubleshooting (port conflicts, npm install failures)

---

## Roadmap

| Phase | Status | Scope |
|---|---|---|
| 1 | Complete | Entry script, module structure, config schema |
| 2 | Complete | Web UI for lab configuration + prerequisite checking |
| 3 | Complete | Hyper-V VM provisioning (`-Create` / `-Destroy`) |
| 4 | Complete | Hybrid guest/domain orchestration and optional Ansible post-provision |

See [`PRD.md`](PRD.md) for full functional requirements and design decisions.
