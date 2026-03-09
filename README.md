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
- Windows Server / client ISO media on local storage
- Windows ADK Deployment Tools (`oscdimg.exe`) for unattended install media generation

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
| --- | --- |
| *(default / `-OpenWebUI`)* | Start Node.js + React web app and open browser |
| `-Validate` | Run prerequisite checks (system, Hyper-V, modules, provisioning tools) |
| `-RemediatePrerequisite -PrerequisiteName <name>` | Execute remediation for a specific prerequisite check |
| `-List` | List lab JSON configs in `Labs/` |
| `-Create -LabName <name>` | Provision Hyper-V and guest/domain orchestration |
| `-Destroy -LabName <name>` | Remove lab VM resources |
| `-Status -LabName <name>` | Return lifecycle + per-VM orchestration progress |
| `-ConfigPath <path>` | Override the default global config path (`Config/defaults.json`) |

---

## Architecture

```tree
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
│   ├── EALabPrerequisites/     # System/provisioning validation + remediation helpers
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
    │       └── prerequisites.js # GET /api/prerequisites/{checks,stream,/} + POST /api/prerequisites/remediate
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
    "displayName": "GPO Test Lab 01"
  },
  "domain": {
    "fqdn": "lab.local",
    "netbiosName": "LAB",
    "functionalLevel": "Win2019"
  },
  "networks": [
    {
      "name": "LabInternal",
      "switchType": "Internal",
      "subnet": "192.168.10.0/24"
    }
  ],
  "baseImages": {
    "windowsServer2022": {
      "isoPath": "E:\\ISOs\\20348.169.210806-2348.fe_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
    }
  },
  "vmDefinitions": [
    {
      "name": "DC01",
      "role": "DomainController",
      "os": "windowsServer2022",
      "generation": 2,
      "hardware": {
        "cpuCount": 2,
        "memoryMB": 4096,
        "diskSizeGB": 80
      },
      "network": "LabInternal"
    }
  ],
  "globalHardwareDefaults": {
    "cpuCount": 2,
    "memoryMB": 2048,
    "diskSizeGB": 60
  },
  "storage": {
    "vmRootPath": "E:\\EALabs"
  }
}
```

**Global defaults** (`Config/defaults.json`) now include guest orchestration defaults (`guestDefaults`) and default credential references (`defaultCredentials`) in addition to VM/storage/image defaults.

### Credential references

- Lab configs should store credential reference keys under `credentials` (for example `localAdminRef`, `domainAdminRef`, `dsrmRef`), not plaintext passwords.
- During `-Create`, the engine resolves refs in this order: `CredentialManager` module -> `cmdkey`/native WinCred fallback -> interactive `Get-Credential` (only when interactive prompting is possible).
- Web launches use a non-interactive PowerShell session, so missing refs fail fast during credential preflight before provisioning starts.
- Domain join uses per-VM `guestConfiguration.domainJoin.credentialRef` first (when configured), then falls back to global `credentials.domainAdminRef`.
- For ephemeral lab environments, configs can also include inline credential fields (`localAdminUser/localAdminPassword`, `domainAdminUser/domainAdminPassword`, `dsrmUser/dsrmPassword`) to allow one-click launches without Credential Manager.

**PowerShell setup example (recommended):**

```powershell
Install-Module CredentialManager -Scope CurrentUser -Force
Import-Module CredentialManager

New-StoredCredential -Target 'ealab-local-admin' -UserName '.\Administrator' -Password '<password>' -Persist LocalMachine
New-StoredCredential -Target 'ealab-domain-admin' -UserName 'CORP\Administrator' -Password '<password>' -Persist LocalMachine
New-StoredCredential -Target 'ealab-dsrm' -UserName 'DSRM' -Password '<password>' -Persist LocalMachine
```

**Web/API credential operations:**

- `GET /api/credentials/status?refs=ealab-local-admin,ealab-domain-admin`
- `POST /api/credentials` with `{ target, username, password, provider }`
- `DELETE /api/credentials/:ref`

If launch fails with missing refs, the launch API returns a `missingCredentialRefs` array for UI remediation.

---

## Prerequisite Checks

`.\Invoke-EALab.ps1 -Validate` (or the Prerequisites tab in the web UI) checks:

| Check | Category | Requirement |
| --- | --- | --- |
| Administrator Elevation | System | Required |
| PowerShell Version | System | 5.1+ |
| Windows Edition | System | Hyper-V-capable edition |
| Hyper-V Feature | Hyper-V | Must be enabled |
| Hyper-V Management Tools | Hyper-V | Must be enabled |
| Hyper-V PowerShell Module | Hyper-V | Required cmdlets available |
| ImportExcel Module | Modules | Required for report exports |
| Disk Space | Storage | Meets configured minimum |
| Default vSwitch | Network | At least one vSwitch found |
| Terraform CLI | Provisioning | Optional for current phase |
| Docker Desktop | Provisioning | Optional for current phase |
| Oscdimg Tool | Provisioning | Required for unattended ISO generation |

Each check returns `Passed`, `Warning`, or `Failed` with remediation hints. In the web UI, warning/failed checks include **Install** and **Docs** actions where remediation is supported.

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

# Remediate a named prerequisite result object
$target = $results | Where-Object Name -eq 'Oscdimg Tool' | Select-Object -First 1
Install-EALabPrerequisite -PrerequisiteResult $target
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
| --- | --- | --- |
| 1 | Complete | Entry script, module structure, config schema |
| 2 | Complete | Web UI for lab configuration + prerequisite checking |
| 3 | Complete | Hyper-V VM provisioning (`-Create` / `-Destroy`) |
| 4 | Complete | Hybrid guest/domain orchestration and optional Ansible post-provision |

See [`PRD.md`](PRD.md) for full functional requirements and design decisions.
