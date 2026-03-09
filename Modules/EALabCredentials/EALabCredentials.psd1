@{
    RootModule        = 'EALabCredentials.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '7d3879a7-b8ec-44da-9ed5-fdd0734a9df8'
    Author            = 'viralarchitect'
    CompanyName       = 'Personal'
    Copyright         = '(c) 2026 viralarchitect. All rights reserved.'
    Description       = 'Credential reference resolution for Enterprise Admin Lab provisioning.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-EALabCredential',
        'Get-EALabCredentialSet',
        'Test-EALabCredentialManagerSupport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('EALab', 'Credentials', 'Security')
            ProjectUri   = ''
            ReleaseNotes = 'Adds Credential Manager reference lookup with Get-Credential fallback.'
        }
    }
}
