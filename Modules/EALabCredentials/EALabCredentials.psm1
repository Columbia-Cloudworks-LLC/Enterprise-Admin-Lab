<#
.SYNOPSIS
    Credential reference resolution for Enterprise Admin Lab.

.DESCRIPTION
    Resolves credential references from Windows Credential Manager when
    available and falls back to interactive prompts when enabled.
#>

Set-StrictMode -Version Latest

function ConvertTo-EALabCredential {
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [SecureString]$SecurePassword
    )

    return [PSCredential]::new($UserName, $SecurePassword)
}

function Get-EALabCredentialFromCredentialManager {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialRef is a lookup key, not a secret value.')]
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CredentialRef
    )

    if (-not (Get-Module -ListAvailable -Name 'CredentialManager')) {
        return $null
    }

    Import-Module CredentialManager -ErrorAction Stop | Out-Null
    $stored = Get-StoredCredential -Target $CredentialRef -ErrorAction SilentlyContinue
    if ($null -eq $stored) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace([string]$stored.UserName) -or
        [string]::IsNullOrWhiteSpace([string]$stored.Password)) {
        return $null
    }

    $securePassword = ConvertTo-SecureString -String ([string]$stored.Password) -AsPlainText -Force
    return ConvertTo-EALabCredential -UserName ([string]$stored.UserName) -SecurePassword $securePassword
}

function Get-EALabCredential {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialRef is a lookup key, not a secret value.')]
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CredentialRef,

        [Parameter(Mandatory = $false)]
        [string]$PromptLabel = 'Lab credential',

        [Parameter(Mandatory = $false)]
        [switch]$AllowPrompt
    )

    if (-not [string]::IsNullOrWhiteSpace($CredentialRef)) {
        try {
            $resolved = Get-EALabCredentialFromCredentialManager -CredentialRef $CredentialRef
            if ($null -ne $resolved) {
                return $resolved
            }
        }
        catch {
            # Fall through to prompt path when enabled.
        }
    }

    if ($AllowPrompt) {
        $promptMessage = if (-not [string]::IsNullOrWhiteSpace($CredentialRef)) {
            "$PromptLabel (`$CredentialRef: $CredentialRef)"
        } else {
            $PromptLabel
        }
        try {
            return Get-Credential -Message "Enter credential for $promptMessage."
        }
        catch {
            $rawMessage = [string]$_.Exception.Message
            if ($rawMessage -match 'NonInteractive mode') {
                $displayRef = if (-not [string]::IsNullOrWhiteSpace($CredentialRef)) { $CredentialRef } else { '<not set>' }
                throw "Credential '$PromptLabel' could not be resolved in this non-interactive session. Configure credentials.*Ref in lab config and store matching values in Windows Credential Manager. Current reference: '$displayRef'."
            }

            throw
        }
    }

    return $null
}

function Get-EALabCredentialSet {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory = $false)]
        [switch]$AllowPrompt
    )

    $credentialConfig = if ($null -ne $Config.credentials) { $Config.credentials } else { [PSCustomObject]@{} }
    $localAdminRef = [string]$credentialConfig.localAdminRef
    $domainAdminRef = [string]$credentialConfig.domainAdminRef
    $dsrmRef = [string]$credentialConfig.dsrmRef

    return [PSCustomObject]@{
        LocalAdmin = Get-EALabCredential -CredentialRef $localAdminRef -PromptLabel 'Local admin credential' -AllowPrompt:$AllowPrompt
        DomainAdmin = if (-not [string]::IsNullOrWhiteSpace($domainAdminRef)) {
            Get-EALabCredential -CredentialRef $domainAdminRef -PromptLabel 'Domain admin credential' -AllowPrompt:$AllowPrompt
        } else {
            $null
        }
        Dsrm = if (-not [string]::IsNullOrWhiteSpace($dsrmRef)) {
            Get-EALabCredential -CredentialRef $dsrmRef -PromptLabel 'DSRM credential' -AllowPrompt:$AllowPrompt
        } else {
            $null
        }
    }
}

function Test-EALabCredentialManagerSupport {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if (Get-Module -ListAvailable -Name 'CredentialManager') {
        return [PSCustomObject]@{
            Supported = $true
            Message = 'CredentialManager module is available.'
        }
    }

    return [PSCustomObject]@{
        Supported = $false
        Message = 'CredentialManager module is not installed. Credential refs will prompt interactively.'
    }
}

Export-ModuleMember -Function @(
    'Get-EALabCredential',
    'Get-EALabCredentialSet',
    'Test-EALabCredentialManagerSupport'
)
