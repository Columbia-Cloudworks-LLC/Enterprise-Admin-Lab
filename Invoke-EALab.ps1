<#
.SYNOPSIS
    Entry point for Enterprise Admin Lab - a Hyper-V based Active Directory
    lab management tool.

.DESCRIPTION
    Invoke-EALab.ps1 is the single entry script for managing Hyper-V lab
    environments. It supports creating, destroying, listing, validating,
    and configuring lab setups via both CLI and GUI interfaces.

    Phase 2: Replaced PowerShell HttpListener + WinForms with a Node.js + React
    web application. Run without parameters to open the web UI.

.PARAMETER Create
    Creates a new lab environment from configuration.
    Requires -LabName. Phase 3 - not yet implemented.

.PARAMETER Destroy
    Destroys an existing lab environment and all its resources.
    Requires -LabName. Phase 3 - not yet implemented.

.PARAMETER List
    Lists all configured lab environments (JSON configs in Labs\).
    Outputs a formatted table with Name, Display Name, VM Count, and Last Modified.

.PARAMETER OpenWebUI
    Opens the Node.js + React web application for lab configuration and management.
    This is the default action when no parameters are specified.

.PARAMETER Validate
    Runs prerequisite checks and validates the system environment.
    Outputs results to the console without opening the GUI.

.PARAMETER RemediatePrerequisite
    Executes remediation for a specific prerequisite check by name.
    Requires -PrerequisiteName.

.PARAMETER Status
    Returns the current lifecycle and VM status for a configured lab.
    Requires -LabName.

.PARAMETER LabName
    The name of a specific lab to operate on.
    Required for -Create, -Destroy, and -Status actions.

.PARAMETER PrerequisiteName
    Name of the prerequisite check to remediate.
    Required for -RemediatePrerequisite.

.PARAMETER ConfigPath
    Path to a custom JSON configuration file.
    Defaults to Config\defaults.json in the project directory.

.PARAMETER SkipOrchestration
    Create action only. Skips post-provision Ansible orchestration and runs
    Hyper-V lifecycle provisioning only.

.EXAMPLE
    .\Invoke-EALab.ps1
    Opens the web application (default action).

.EXAMPLE
    .\Invoke-EALab.ps1 -OpenWebUI
    Explicitly opens the web application.

.EXAMPLE
    .\Invoke-EALab.ps1 -Validate
    Runs all prerequisite checks and outputs a results table.

.EXAMPLE
    .\Invoke-EALab.ps1 -RemediatePrerequisite -PrerequisiteName 'Terraform CLI'
    Attempts to install/fix the named prerequisite using built-in remediation logic.

.EXAMPLE
    .\Invoke-EALab.ps1 -Create -LabName 'TestLab01'
    Creates a new lab named TestLab01 (Phase 3).

.EXAMPLE
    .\Invoke-EALab.ps1 -Destroy -LabName 'TestLab01'
    Destroys the lab named TestLab01 (Phase 3).

.EXAMPLE
    .\Invoke-EALab.ps1 -List
    Lists all configured lab JSON configs.

.NOTES
    Author: viralarchitect
    Product: Enterprise Admin Lab
    Version: 3.0.0

.LINK
    https://github.com/viralarchitect/PowerShell
#>
#Requires -Version 5.1
# NOTE: RunAsAdministrator is NOT required at script level so that -Validate
# can be called from the web server without elevation.  Per-action checks below
# enforce admin where it is genuinely needed (Create / Destroy).

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'OpenWebUI')]
param(
    [Parameter(ParameterSetName = 'Create', Mandatory = $true)]
    [switch]$Create,

    [Parameter(ParameterSetName = 'Destroy', Mandatory = $true)]
    [switch]$Destroy,

    [Parameter(ParameterSetName = 'List', Mandatory = $true)]
    [switch]$List,

    [Parameter(ParameterSetName = 'OpenWebUI')]
    [switch]$OpenWebUI,

    [Parameter(ParameterSetName = 'Validate', Mandatory = $true)]
    [switch]$Validate,

    [Parameter(ParameterSetName = 'RemediatePrerequisite', Mandatory = $true)]
    [switch]$RemediatePrerequisite,

    [Parameter(ParameterSetName = 'Status', Mandatory = $true)]
    [switch]$Status,

    [Parameter(ParameterSetName = 'Create', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Destroy', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Status', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LabName,

    [Parameter(ParameterSetName = 'Destroy')]
    [switch]$DeleteLabData,

    [Parameter(ParameterSetName = 'Create')]
    [switch]$SkipOrchestration,

    [Parameter(ParameterSetName = 'Create')]
    [switch]$Force,

    [Parameter(ParameterSetName = 'RemediatePrerequisite', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PrerequisiteName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Determine elevation state once; used to gate admin-only parameter sets.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltinRole]::Administrator)

# --------------------------------------------------------------------------
# Setup: module path and imports
# --------------------------------------------------------------------------
$scriptDir = $PSScriptRoot
$modulesDir = Join-Path $scriptDir 'Modules'

# Temporarily prepend our Modules directory to PSModulePath
$originalModulePath = $env:PSModulePath
$env:PSModulePath = "$modulesDir;$env:PSModulePath"

$debugEnabled = $PSBoundParameters.ContainsKey('Debug') -and [bool]$PSBoundParameters['Debug']
if ($debugEnabled) {
    $VerbosePreference = 'Continue'
}

Write-Debug ("Invoke-EALab start. ParameterSet='{0}', LabName='{1}', ConfigPath='{2}', IsAdmin={3}, ScriptDir='{4}'." -f `
        $PSCmdlet.ParameterSetName, [string]$LabName, [string]$ConfigPath, $isAdmin, $scriptDir)
Write-Debug "Modules directory prepended to PSModulePath: $modulesDir"

try {
    # Import project modules (EALabUI and EALabWebUI are retired)
    Write-Debug 'Importing EALab modules: EALabConfig, EALabPrerequisites, EALabProvisioning.'
    Import-Module (Join-Path $modulesDir 'EALabConfig\EALabConfig.psd1')         -Force -ErrorAction Stop
    Import-Module (Join-Path $modulesDir 'EALabPrerequisites\EALabPrerequisites.psd1') -Force -ErrorAction Stop
    Import-Module (Join-Path $modulesDir 'EALabProvisioning\EALabProvisioning.psd1') -Force -ErrorAction Stop

    # Set default config path if not specified
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $scriptDir 'Config\defaults.json'
    }
    Write-Debug "Effective ConfigPath: $ConfigPath"

    # Route to the appropriate action
    Write-Debug "Routing to action parameter set: $($PSCmdlet.ParameterSetName)"
    switch ($PSCmdlet.ParameterSetName) {
        'OpenWebUI' {
            Write-Debug 'OpenWebUI selected. Validating Node.js runtime.'
            # Verify Node.js is available
            try {
                $nodeVersion = & node --version 2>&1
                Write-Host "[INFO] Found Node.js: $nodeVersion" -ForegroundColor Green
                Write-Debug "Node.js version detected: $nodeVersion"
            }
            catch {
                Write-Debug "Node.js version check failed: $($_.Exception.Message)"
                Write-Error "Node.js is not installed or not in PATH. Please install Node.js 20 LTS from https://nodejs.org/"
                exit 1
            }

            # Path to the web application directory
            $webDir = Join-Path $scriptDir 'Web'
            if (-not (Test-Path -PathType Container $webDir)) {
                Write-Error "Web directory not found at: $webDir"
                exit 1
            }
            Write-Debug "Web directory resolved: $webDir"

            # Check if node_modules exists; if not, run npm install
            $nodeModulesPath = Join-Path $webDir 'node_modules'
            if (-not (Test-Path -PathType Container $nodeModulesPath)) {
                Write-Host "[INFO] Installing dependencies with npm install..." -ForegroundColor Cyan
                Write-Debug "node_modules missing at '$nodeModulesPath'. Running npm install."
                Push-Location $webDir
                try {
                    & npm install 2>&1 | Out-Host
                    if ($LASTEXITCODE -ne 0) {
                        Write-Debug "npm install failed with exit code: $LASTEXITCODE"
                        Write-Error "npm install failed with exit code $LASTEXITCODE"
                        exit 1
                    }
                    Write-Debug 'npm install completed successfully.'
                }
                finally {
                    Pop-Location
                }
            }
            else {
                Write-Debug "node_modules already present at '$nodeModulesPath'. Skipping npm install."
            }

            # Idempotent teardown: kill any process already listening on the dev ports
            foreach ($serverPort in @(47001, 47173)) {
                $existing = Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue |
                            Select-Object -First 1
                if ($existing) {
                    Write-Host "[INFO] Stopping existing process on port $serverPort (PID: $($existing.OwningProcess))..." -ForegroundColor Yellow
                    Write-Debug "Stopping stale listener on port $serverPort with PID $($existing.OwningProcess)."
                    Stop-Process -Id $existing.OwningProcess -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                }
                else {
                    Write-Debug "No existing listener on port $serverPort."
                }
            }

            # Start both Express API and Vite dev server via npm run dev (concurrently)
            Write-Host "[INFO] Starting Node.js development server..." -ForegroundColor Cyan
            Write-Debug "Starting npm dev process in '$webDir'."
            $previousWebDebugEnv = $env:EALAB_DEBUG_WEB
            if ($debugEnabled) {
                Write-Debug 'PowerShell -Debug detected. Enabling web server debug output via EALAB_DEBUG_WEB=1.'
                $env:EALAB_DEBUG_WEB = '1'
            }
            $nodeProcess = Start-Process -FilePath 'npm.cmd' -ArgumentList 'run', 'dev' `
                -WorkingDirectory $webDir -PassThru -NoNewWindow
            if ($debugEnabled) {
                if ([string]::IsNullOrWhiteSpace([string]$previousWebDebugEnv)) {
                    Remove-Item Env:EALAB_DEBUG_WEB -ErrorAction SilentlyContinue
                }
                else {
                    $env:EALAB_DEBUG_WEB = $previousWebDebugEnv
                }
            }

            # Give concurrently time to spin up both Express and Vite
            Start-Sleep -Seconds 4
            Write-Debug "npm dev process state after startup wait: HasExited=$($nodeProcess.HasExited), PID=$($nodeProcess.Id)"

            if ($nodeProcess.HasExited) {
                Write-Error "Node.js process exited unexpectedly. Check the Web directory and server/index.js."
                exit 1
            }
            Write-Host "[INFO] Node.js server started (PID: $($nodeProcess.Id))" -ForegroundColor Green

            Write-Host "[INFO] Opening web application in default browser..." -ForegroundColor Cyan
            Write-Debug 'Launching browser URL http://localhost:47173/.'

            # Open the browser to the web app (Vite dev server on 47173)
            Start-Process "http://localhost:47173/"

            Write-Host "[INFO] Web application is running." -ForegroundColor Green
            Write-Host "[INFO] Press Ctrl+C in the terminal to stop the server." -ForegroundColor Yellow
            Write-Host ""

            # Wait for the process to exit (Ctrl+C will cause it)
            try {
                Wait-Process -Id $nodeProcess.Id
            }
            catch {
                Write-Debug "Wait-Process returned early: $($_.Exception.Message)"
                # Process was terminated externally
            }

            Write-Host "[INFO] Server stopped." -ForegroundColor Cyan
            Write-Debug 'OpenWebUI flow completed.'
        }

        'Validate' {
            Write-Debug 'Validate selected. Running Test-EALabPrerequisites.'
            Write-Host '' -ForegroundColor Cyan
            Write-Host '  Enterprise Admin Lab - System Validation' -ForegroundColor Cyan
            Write-Host '  ========================================' -ForegroundColor Cyan
            Write-Host ''

            $results = Test-EALabPrerequisites
            Write-Debug "Validation produced $(@($results).Count) result rows."

            # Display results as formatted table
            foreach ($result in $results) {
                $statusTag = switch ($result.Status) {
                    'Passed'  { '[OK]' }
                    'Failed'  { '[FAIL]' }
                    'Warning' { '[WARN]' }
                    default   { '[??]' }
                }

                $color = switch ($result.Status) {
                    'Passed'  { 'Green' }
                    'Failed'  { 'Red' }
                    'Warning' { 'Yellow' }
                    default   { 'White' }
                }

                $paddedStatus = $statusTag.PadRight(7)
                $paddedName = $result.Name.PadRight(28)
                $paddedCategory = $result.Category.PadRight(10)

                Write-Host "  $paddedStatus" -ForegroundColor $color -NoNewline
                Write-Host " $paddedName $paddedCategory $($result.Message)"
            }

            Write-Host ''
            $summary = Get-EALabPrerequisiteSummary -Results $results
            Write-Host "  $summary" -ForegroundColor Cyan
            Write-Host ''
            Write-Debug "Validation summary: $summary"

            # Also output results as objects for pipeline consumption
            $results
        }

        'Create' {
            Write-Debug "Create selected for lab '$LabName' (SkipOrchestration=$SkipOrchestration, Force=$Force)."
            if (-not $isAdmin) {
                Write-Error "The -Create action requires an elevated (Run as Administrator) session."
                exit 1
            }

            Write-Host '' -ForegroundColor Cyan
            Write-Host "  Enterprise Admin Lab - Create '$LabName'" -ForegroundColor Cyan
            Write-Host '  ======================================' -ForegroundColor Cyan
            Write-Host ''

            $result = New-EALabEnvironment -LabName $LabName -Force:$Force -SkipOrchestration:$SkipOrchestration -ErrorAction Stop
            Write-Debug "Create completed. Status=$($result.Status); VMCount=$(@($result.VMs).Count); LogFile=$($result.LogFile)"
            Write-Host "[OK] $($result.Message)" -ForegroundColor Green
            if ($result.VMs.Count -gt 0) {
                Write-Host "[INFO] Provisioned VMs: $($result.VMs -join ', ')" -ForegroundColor Cyan
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$result.AnsibleLog)) {
                Write-Host "[INFO] Ansible log: $($result.AnsibleLog)" -ForegroundColor Cyan
            }
        }

        'RemediatePrerequisite' {
            Write-Debug "RemediatePrerequisite selected for '$PrerequisiteName'."

            if (-not $isAdmin) {
                Write-Error "The -RemediatePrerequisite action requires an elevated (Run as Administrator) session."
                exit 1
            }

            $results = Test-EALabPrerequisites
            $target = $results | Where-Object { $_.Name -eq $PrerequisiteName } | Select-Object -First 1
            if ($null -eq $target) {
                Write-Error "Unknown prerequisite '$PrerequisiteName'."
                exit 1
            }

            if ($target.Status -eq 'Passed') {
                Write-Host "[OK] Prerequisite '$PrerequisiteName' is already satisfied." -ForegroundColor Green
                exit 0
            }

            $ok = Install-EALabPrerequisite -PrerequisiteResult $target
            if (-not $ok) {
                Write-Error "No remediation was executed for '$PrerequisiteName'."
                exit 1
            }

            Write-Host "[OK] Remediation executed for '$PrerequisiteName'." -ForegroundColor Green
        }

        'Destroy' {
            Write-Debug "Destroy selected for lab '$LabName' (DeleteLabData=$DeleteLabData)."
            if (-not $isAdmin) {
                Write-Error "The -Destroy action requires an elevated (Run as Administrator) session."
                exit 1
            }

            Write-Host '' -ForegroundColor Cyan
            Write-Host "  Enterprise Admin Lab - Destroy '$LabName'" -ForegroundColor Cyan
            Write-Host '  =======================================' -ForegroundColor Cyan
            Write-Host ''

            $result = Remove-EALabEnvironment -LabName $LabName -DeleteLabData:$DeleteLabData -ErrorAction Stop
            Write-Debug "Destroy completed. Removed VM count=$(@($result.Removed).Count); LogFile=$($result.LogFile)"
            Write-Host "[OK] Lab '$LabName' resources removed." -ForegroundColor Green
            if ($result.Removed.Count -gt 0) {
                Write-Host "[INFO] Removed VMs: $($result.Removed -join ', ')" -ForegroundColor Cyan
            }
        }

        'List' {
            Write-Debug 'List selected. Enumerating lab configurations.'
            Write-Host '' -ForegroundColor Cyan
            Write-Host '  Enterprise Admin Lab - Configured Labs' -ForegroundColor Cyan
            Write-Host '  ======================================' -ForegroundColor Cyan
            Write-Host ''

            $labs = Get-EALabConfigs
            Write-Debug "Found $(@($labs).Count) lab configuration files."
            if ($labs.Count -eq 0) {
                Write-Host '  No lab configurations found.' -ForegroundColor Yellow
                Write-Host '  Use -OpenConfigUI to create a new lab configuration.' -ForegroundColor Cyan
            }
            else {
                $labsWithStatus = foreach ($lab in $labs) {
                    $status = 'NotCreated'
                    try {
                        Write-Debug "Querying status for lab '$($lab.Name)'."
                        $statusResult = Get-EALabEnvironmentStatus -LabName $lab.Name -ErrorAction Stop
                        if ($null -ne $statusResult -and -not [string]::IsNullOrWhiteSpace($statusResult.Status)) {
                            $status = $statusResult.Status
                        }
                    }
                    catch {
                        Write-Debug "Failed to query status for lab '$($lab.Name)': $($_.Exception.Message)"
                        $status = 'Error'
                    }

                    [PSCustomObject]@{
                        Name         = $lab.Name
                        DisplayName  = $lab.DisplayName
                        VMCount      = $lab.VMCount
                        LastModified = $lab.LastModified
                        Status       = $status
                    }
                }

                $labsWithStatus |
                    Format-Table -AutoSize | Out-String | Write-Host
            }
            Write-Host ''
        }

        'Status' {
            Write-Debug "Status selected for lab '$LabName'."
            Write-Host '' -ForegroundColor Cyan
            Write-Host "  Enterprise Admin Lab - Status '$LabName'" -ForegroundColor Cyan
            Write-Host '  =====================================' -ForegroundColor Cyan
            Write-Host ''

            $status = Get-EALabEnvironmentStatus -LabName $LabName -ErrorAction Stop
            Write-Debug "Status query result: Status=$($status.Status); Step=$($status.Step); ExpectedVMs=$($status.ExpectedVMs); RunningVMs=$($status.RunningVMs)"
            Write-Host "[INFO] Lifecycle: $($status.Status)" -ForegroundColor Cyan
            if (-not [string]::IsNullOrWhiteSpace([string]$status.Step)) {
                Write-Host "[INFO] Step: $($status.Step)" -ForegroundColor Cyan
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$status.Message)) {
                Write-Host "[INFO] Message: $($status.Message)" -ForegroundColor Cyan
            }
            Write-Host "[INFO] Expected VMs: $($status.ExpectedVMs) | Running: $($status.RunningVMs)" -ForegroundColor Cyan

            if ($null -ne $status.Details -and $status.Details.PSObject.Properties.Name -contains 'vmProgress') {
                Write-Host ''
                Write-Host '  VM Progress' -ForegroundColor Cyan
                Write-Host '  ----------' -ForegroundColor Cyan
                foreach ($item in $status.Details.vmProgress.PSObject.Properties) {
                    $vmProgress = $item.Value
                    Write-Host ("  {0,-20} {1,-20} {2}" -f $item.Name, [string]$vmProgress.phase, [string]$vmProgress.status)
                }
            }

            Write-Host ''
            $status
        }
    }
}
catch {
    Write-Debug "Invoke-EALab top-level catch: $($_.Exception.Message)"
    Write-Error "Failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # --------------------------------------------------------------------------
    # Cleanup: restore original module path
    # --------------------------------------------------------------------------
    Write-Debug 'Restoring original PSModulePath.'
    $env:PSModulePath = $originalModulePath
}
