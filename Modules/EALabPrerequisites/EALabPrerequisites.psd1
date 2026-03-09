@{
    RootModule        = 'EALabPrerequisites.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'b2c3d4e5-4444-5555-6666-112233445566'
    Author            = 'viralarchitect'
    CompanyName       = 'Personal'
    Copyright         = '(c) 2026 viralarchitect. All rights reserved.'
    Description       = 'Prerequisite checking and remediation module for Enterprise Admin Lab.'
    PowerShellVersion = '5.1'
    RequiredModules   = @(
        @{ModuleName = 'EALabConfig'; ModuleVersion = '2.0.0'; GUID = 'a1b2c3d4-1111-2222-3333-aabbccddeeff'},
        @{ModuleName = 'EALabCredentials'; ModuleVersion = '1.0.0'; GUID = '7d3879a7-b8ec-44da-9ed5-fdd0734a9df8'}
    )
    FunctionsToExport = @('Test-EALabPrerequisites', 'Install-EALabPrerequisite', 'Get-EALabPrerequisiteSummary', 'Test-EALabProvisioningReadiness')
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('EALab', 'Prerequisites', 'HyperV', 'Lab')
            ProjectUri   = ''
            ReleaseNotes = 'Phase 2: Added Provisioning checks for Terraform CLI and Docker Desktop.'
        }
    }
}
