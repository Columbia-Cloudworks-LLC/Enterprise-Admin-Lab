@{
    RootModule        = 'EALabUnattend.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '93045525-4da6-4d5c-8b11-9f909e49f0e8'
    Author            = 'viralarchitect'
    CompanyName       = 'Personal'
    Copyright         = '(c) 2026 viralarchitect. All rights reserved.'
    Description       = 'Generates and attaches unattended setup artifacts for Enterprise Admin Lab VMs.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'New-EALabVmUnattendXml',
        'New-EALabUnattendMedia',
        'Set-EALabVmInstallMedia'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('EALab', 'Unattend', 'HyperV')
            ProjectUri   = ''
            ReleaseNotes = 'Adds unattended answer file generation and media attachment helpers.'
        }
    }
}
