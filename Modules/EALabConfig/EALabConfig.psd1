@{
    RootModule        = 'EALabConfig.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'a1b2c3d4-1111-2222-3333-aabbccddeeff'
    Author            = 'viralarchitect'
    CompanyName       = 'Personal'
    Copyright         = '(c) 2026 viralarchitect. All rights reserved.'
    Description       = 'Configuration read/write/validation module for Enterprise Admin Lab.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-EALabConfigPath',
        'Get-EALabDefaultConfig',
        'Test-EALabConfig',
        'Get-EALabConfig',
        'Get-EALabConfigs',
        'Set-EALabConfig',
        'New-EALabConfig',
        'Remove-EALabConfig',
        'Copy-EALabConfig'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('EALab', 'Config', 'HyperV', 'Lab')
            ProjectUri   = ''
            ReleaseNotes = 'Phase 2: Added per-lab config CRUD (Get/Set/New/Remove/Copy-EALabConfig), per-lab Test-EALabConfig validation, and defaults.json v2.0 migration guard.'
        }
    }
}
