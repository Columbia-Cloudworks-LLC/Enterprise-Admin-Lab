@{
    RootModule        = 'EALabProvisioning.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f7627f4d-0f83-46a7-b09b-f8da1826b8ab'
    Author            = 'viralarchitect'
    CompanyName       = 'Personal'
    Copyright         = '(c) 2026 viralarchitect. All rights reserved.'
    Description       = 'Hyper-V provisioning and lifecycle module for Enterprise Admin Lab.'
    PowerShellVersion = '5.1'
    RequiredModules   = @(
        @{ ModuleName = 'EALabConfig'; ModuleVersion = '2.0.0'; GUID = 'a1b2c3d4-1111-2222-3333-aabbccddeeff' },
        @{ ModuleName = 'EALabPrerequisites'; ModuleVersion = '2.0.0'; GUID = 'b2c3d4e5-4444-5555-6666-112233445566' },
        @{ ModuleName = 'EALabCredentials'; ModuleVersion = '1.0.0'; GUID = '7d3879a7-b8ec-44da-9ed5-fdd0734a9df8' },
        @{ ModuleName = 'EALabUnattend'; ModuleVersion = '1.0.0'; GUID = '93045525-4da6-4d5c-8b11-9f909e49f0e8' },
        @{ ModuleName = 'EALabGuestOrchestration'; ModuleVersion = '1.0.0'; GUID = '0cad9916-8ce7-44dd-ac4f-b77294577f64' }
    )
    FunctionsToExport = @(
        'New-EALabEnvironment',
        'Remove-EALabEnvironment',
        'Get-EALabEnvironmentStatus'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('EALab', 'Provisioning', 'HyperV', 'Lab')
            ProjectUri   = ''
            ReleaseNotes = 'Phase 3: Added VM launch, destroy, and status lifecycle functions.'
        }
    }
}
