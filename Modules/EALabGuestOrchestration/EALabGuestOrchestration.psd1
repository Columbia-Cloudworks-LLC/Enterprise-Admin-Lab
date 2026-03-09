@{
    RootModule        = 'EALabGuestOrchestration.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '0cad9916-8ce7-44dd-ac4f-b77294577f64'
    Author            = 'viralarchitect'
    CompanyName       = 'Personal'
    Copyright         = '(c) 2026 viralarchitect. All rights reserved.'
    Description       = 'Guest baseline and domain orchestration helpers for Enterprise Admin Lab.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Wait-EALabVmInstallReady',
        'Invoke-EALabGuestCommand',
        'Initialize-EALabGuestBaseline',
        'Enable-EALabGuestRemoting',
        'Install-EALabGuestTools',
        'Invoke-EALabDomainControllerPromotion',
        'Wait-EALabDomainReadiness',
        'Join-EALabMachineToDomain'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('EALab', 'Guest', 'Orchestration')
            ProjectUri   = ''
            ReleaseNotes = 'Adds guest baseline, DC promotion, and domain join helpers.'
        }
    }
}
