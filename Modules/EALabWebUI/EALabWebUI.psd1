@{
    RootModule        = 'EALabWebUI.psm1'
    ModuleVersion     = '3.0.0'
    GUID              = 'd4e5f6a7-aaaa-bbbb-cccc-112233445566'
    Author            = 'viralarchitect'
    CompanyName       = 'Personal'
    Copyright         = '(c) 2026 viralarchitect. All rights reserved.'
    Description       = 'RETIRED: Replaced by Node.js web application. Run Invoke-EALab.ps1 with no arguments.'
    PowerShellVersion = '5.1'
    RequiredModules   = @()
    FunctionsToExport = @()
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('EALab', 'WebUI', 'HTTP', 'HyperV', 'Lab')
            ProjectUri   = ''
            ReleaseNotes = 'Phase 2: Initial release. Background HttpListener runspace serving the self-contained HTML lab configuration form. Supports New and Edit modes.'
        }
    }
}
