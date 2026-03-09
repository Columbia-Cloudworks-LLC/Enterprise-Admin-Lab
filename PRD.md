# Enterprise Admin Lab - Product Requirements Document

## 1. Product overview

**Product Name:** Enterprise Admin Lab

**Summary:**  
Enterprise Admin Lab is a PowerShell‑based toolset that lets Windows Server admins define, spin up, and destroy small, fully scripted Hyper‑V AD labs on a Windows 11 Pro host using a configuration‑driven workflow. The product exposes a single PowerShell entry script and a GUI‑driven configuration manager (HTML + WinForms) for defining lab templates without requiring admins to learn Terraform/Ansible internals. [learn.microsoft](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/powershell)

**Primary platform:**

- Host OS: Windows 11 Pro with Hyper‑V role and PowerShell 5.1+ / PowerShell 7.x. [techcommunity.microsoft](https://techcommunity.microsoft.com/blog/educatordeveloperblog/step-by-step-how-to-create-a-windows-11-vm-on-hyper-v-via-powershell/3754100)
- Hyper‑V managed using native Hyper‑V PowerShell cmdlets. [techtarget](https://www.techtarget.com/searchwindowsserver/tutorial/How-PowerShell-can-automate-Hyper-V-deployments)

***

## 2. Target users and use cases

**Users:**

- Enterprise Windows Server / AD administrators.
- DevOps/SREs working with hybrid identity and AD‑integrated apps.
- Trainers and internal enablement teams building repeatable AD exercises.

**Core use cases:**

- Rapidly stand up a “mini enterprise” AD forest to:
  - Test GPOs, login scripts, security baselines.
  - Practice AD break/fix (replication, SYSVOL, DNS, time, USN rollback).
  - Validate PowerShell automation against realistic AD/Server topologies.
- Tear down labs completely and rebuild from scratch in minutes using the same configuration.
- Maintain a catalog of reusable “lab templates” stored as config files.

***

## 3. Product goals and non‑goals

**Goals:**

- Provide a single PowerShell entry script that covers:
  - Lab creation.
  - Lab destruction.
  - Lab status and basic health checks.
  - Launching the configuration manager GUI.
- Let admins define lab templates entirely via GUI, then modify them later via GUI or direct config file edits.
- Make all lab behavior driven by configuration files (no hard‑coded topology).
- Avoid dependencies on external infrastructure (no mandatory Azure/AWS).

**Non‑goals (v1):**

- Not a general‑purpose Hyper‑V management suite.
- Not a full DSC engine replacement.
- No requirement to support non‑Windows hosts (WSL/Proxmox/VMware).

***

## 4. High‑level architecture

**Components:**

1. **Entry script:** `Invoke-EALab.ps1`
   - Single entry point with subcommands (or parameters) like `-Create`, `-Destroy`, `-List`, `-OpenConfigUI`.
2. **Configuration manager GUI:**
   - HTML‑based UI rendered via embedded browser control or IE/Edge COM object to host a form‑like GUI from PowerShell. [stackoverflow](https://stackoverflow.com/questions/5981905/use-html-form-as-gui-for-powershell)
   - WinForms‑based GUI for native experience on the host (can be used instead of or in addition to HTML). [foxdeploy](https://www.foxdeploy.com/blog/creating-a-gui-natively-for-your-powershell-tools-using-net-methods)
3. **Config store:**
   - Set of JSON/YAML files describing:
     - Lab definitions (topology, VM specs, roles).
     - Global defaults (paths, base images, naming conventions).
4. **Lab engine:**
   - PowerShell modules/functions that:
     - Validate config.
     - Use Hyper‑V cmdlets to create vSwitches, VMs, virtual disks. [learn.microsoft](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/powershell)
     - Inject first‑boot scripts and credentials.
     - Create or configure an Ansible controller VM.
5. **Ansible integration layer:**
   - Scripts that, after VM provisioning, trigger Ansible playbooks (living inside a controller VM or within the repo) to:
     - Promote DCs.
     - Join member servers/clients to the domain.
     - Apply baseline configuration and “break” scenarios.

***

## 5. Functional requirements

### 5.1 Entry script behavior

**FR‑1:** The tool MUST provide a single entry script `Invoke-EALab.ps1` callable from an elevated PowerShell session.

**FR‑2:** The entry script MUST support the following primary actions:

- `New` / `-Create` – create a lab from a named config.
- `Remove` / `-Destroy` – destroy all resources of a named lab.
- `Get` / `-List` – list existing labs and their lifecycle state.
- `-Status` – return lifecycle and per-VM orchestration progress for a lab.
- `Config` / `-OpenConfigUI` – open the configuration manager GUI.
- `Test` / `-Validate` – validate a lab config without creating resources.

**FR‑3:** The script MUST accept:

- `-LabName` to identify the lab.
- `-ConfigPath` (optional) to override default config directory.
- `-WhatIf` to simulate operations.
- Credential references in lab config (`credentials.localAdminRef`, `credentials.domainAdminRef`, `credentials.dsrmRef`) with runtime secure resolution.

**FR‑4:** The script MUST surface clear, human‑readable status and error messages suitable for logs.

### 5.2 Configuration model

**FR‑5:** Lab definitions MUST be stored as files (JSON or YAML) on disk, under a default directory (e.g. `.\Labs`).

**FR‑6:** Each lab config MUST support:

- Lab metadata: `Name`, `Description`, `Version`.
- Domain settings: `DomainFQDN`, `NetBIOSName`, forest/domain functional level.
- Network: list of subnets, vSwitch types (Internal/External), mapping to Hyper‑V switches.
- VM types: DC, member server, client, Ansible controller, etc.
- VM properties per type:
  - Count.
  - CPU, RAM, disk size.
  - OS image path / template.
  - Network attachment(s).
  - Role tags (e.g. `DC`, `FileServer`, `BreakableDC`).
- Ansible parameters:
  - Whether to create controller VM.
  - Inventory group mappings for each VM role.
  - Playbook list to run pre/post‑creation.

**FR‑7:** The configuration format MUST be versioned to allow future schema changes.

**FR‑8:** All behavior (VM names, OU structure, installed roles) SHOULD be driven from config or Ansible, not hard‑coded in PowerShell.

### 5.3 Configuration manager GUI

**FR‑9:** The product MUST provide a GUI for creating and editing lab configs.

**FR‑10:** The GUI MUST be callable from:

- Start menu shortcut (optional, v2).
- `Invoke-EALab.ps1 -OpenConfigUI`.

**FR‑11:** The GUI MUST allow:

- Creating a new lab configuration.
- Editing an existing lab configuration selected from a list.
- Copying an existing config to use as a template.
- Validating config before saving (basic checks: unique names, valid paths, plausible resource sizes).

**FR‑12:** The GUI MUST expose the following fields at minimum:

- Lab name, description.
- Domain settings (FQDN, NetBIOS).
- VM counts and types.
- Per‑VM‑type hardware specs (CPU/RAM/disk).
- Base image paths (browsable file picker).
- Network definitions (subnet, switch selection, type).
- Ansible options (enable/disable, controller specs).

**FR‑13:** The GUI implementation:

- MAY use WinForms for the main interactive UI. [bytecookie.wordpress](https://bytecookie.wordpress.com/2011/07/17/gui-creation-with-powershell-the-basics/)
- MAY supplement with an HTML‑based UI hosted via browser control for more complex forms. [techtarget](https://www.techtarget.com/searchitoperations/tutorial/Boost-productivity-with-these-PowerShell-GUI-examples)
- MUST separate GUI layout from business logic (e.g., dedicated functions for file IO and validation). [devblogs.microsoft](https://devblogs.microsoft.com/scripting/ive-got-a-powershell-secret-adding-a-gui-to-scripts/)

**FR‑14:** Once a lab config is saved, admins MUST be able to use the entry script without reopening the GUI.

### 5.4 Lab lifecycle management

**FR‑15:** `-Create` MUST:

- Load and validate the lab config.
- Ensure required Hyper‑V features are enabled; otherwise, fail with a clear error. [techcommunity.microsoft](https://techcommunity.microsoft.com/blog/educatordeveloperblog/step-by-step-how-to-create-a-windows-11-vm-on-hyper-v-via-powershell/3754100)
- Create required vSwitches if missing.
- Create VMs according to config (generation, CPU/RAM, disks).
- Attach VMs to appropriate vSwitches.
- Configure boot order and Secure Boot templates as required.
- Inject first‑boot customization (unattend.xml or PowerShell) for:
  - Local admin account.
  - Enabling WinRM.
  - Network configuration (IP / DHCP as configured).
- Optionally provision an Ansible controller VM and copy/play initial playbooks.

**FR‑16:** `-Destroy` MUST:

- Shut down all VMs belonging to the lab.
- Remove those VMs from Hyper‑V.
- Optionally delete lab‑owned VHDX files and checkpoints (configurable safety switch).
- Preserve config files and logs.

**FR‑17:** `-List` MUST show:

- Lab name.
- Lab status (NotCreated, Creating, Running, Error, Destroying, Destroyed).
- Count of VMs per lab.
- Basic resource summary (total vCPUs, RAM assigned).

### 5.5 Ansible controller integration

**FR‑18:** Lab creation MUST support an option to include an Ansible controller VM (Linux).

**FR‑19:** When enabled, the tool MUST:

- Provision the controller VM with specified resources and image.
- Inject a cloud‑init or first‑boot script to:
  - Install Ansible and required collections.
  - Clone/pull the lab’s playbook repo (path configurable).
- Generate an inventory file mapping lab hosts into Ansible groups.

**FR‑20:** The system SHOULD expose a switch/flag that, after successful VM creation, triggers a default “bring‑up” playbook (e.g., promote DC, join domain, apply base GPO).

**FR-20a:** The orchestration model SHOULD be hybrid by default: Hyper-V lifecycle (create/destroy) remains in PowerShell while guest/domain configuration executes through Ansible playbooks.

**FR-20b:** A break-glass option MUST exist to run Hyper-V lifecycle without post-provision Ansible orchestration.

**FR-20c:** The default orchestration flow MUST gate domain join behind successful primary DC promotion/readiness and report per-VM orchestration phases in lifecycle status details.

***

## 6. Non‑functional requirements

**NFR‑1 – Performance:**  
On a host with adequate resources, a “small” lab (1 DC, 1 member server, 1 client, 1 controller) SHOULD be fully provisioned (VM creation + base config) in under 15 minutes, assuming images are local.

**NFR‑2 – Idempotency:**  
Running `-Create` with the same lab name and config MUST NOT duplicate resources; it SHOULD detect existing resources and either fail with a clear message or reconcile consistently.

**NFR‑3 – Safety:**  

- Default behavior MUST NOT delete base images.
- Destructive operations (e.g., deleting VHDX) MUST require explicit flags.

**NFR‑4 – Observability:**  

- All operations MUST write logs to a configurable folder per lab.
- Errors MUST include enough context to recreate or debug (VM name, step, script block).

**NFR‑5 – Usability:**  

- The GUI MUST be usable by admins with no PowerShell scripting experience (clear labels, tooltips for advanced options). [blog.inedo](https://blog.inedo.com/powershell/gui)
- CLI help (`Get-Help Invoke-EALab.ps1 -Detailed`) MUST document all parameters and include examples.

***

## 7. UX flows

### 7.1 First‑time setup

1. Admin installs repo (Git clone or ZIP).
2. Admin runs `.\Invoke-EALab.ps1 -OpenConfigUI`.
3. GUI prompts for:
   - Global defaults (base path, image locations).
   - First lab template (e.g., “SingleSite‑GPO‑Lab”).
4. Admin saves lab definition.
5. Admin runs `.\Invoke-EALab.ps1 -Create -LabName SingleSite-GPO-Lab`.

### 7.2 Daily usage

- Typical admin flow becomes:
  - `.\Invoke-EALab.ps1 -Create -LabName GpoTest01`
  - Work in the lab from a jump box.
  - `.\Invoke-EALab.ps1 -Destroy -LabName GpoTest01`

The GUI is only revisited to create/update templates.

***

## 8. Constraints and dependencies

- Windows 11 Pro with Hyper‑V feature enabled and sufficient hardware resources (RAM, disk). [techcommunity.microsoft](https://techcommunity.microsoft.com/blog/educatordeveloperblog/step-by-step-how-to-create-a-windows-11-vm-on-hyper-v-via-powershell/3754100)
- PowerShell 5.1+; support for PowerShell 7.x is desirable.
- Local admin rights on host.
- Access to Windows Server and client ISO/VHDX images.
- (Optional) Internet access from controller VM for Ansible package installation.

***

## 9. Open questions / v2 ideas

- Support for exporting/importing labs between hosts.
- Direct Terraform/Ansible config generation from the same UI (for hybrid scenarios).
- Support for nested virtualization or Proxmox/VMware backends later.
- Role‑based prebuilt “scenario packs” (e.g., security labs, DR drills) selectable from the GUI.

If you’d like, the next step can be a skeleton repo layout plus a rough `Invoke-EALab.ps1` parameter design and function breakdown that maps directly to this PRD.
