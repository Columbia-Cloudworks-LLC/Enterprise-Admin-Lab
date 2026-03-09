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

function ConvertTo-EALabCredentialFromPlainText {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'Ephemeral lab configs may explicitly contain test credentials for one-click bring-up.')]
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace($UserName) -or [string]::IsNullOrWhiteSpace($Password)) {
        return $null
    }

    $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $credential = ConvertTo-EALabCredential -UserName $UserName -SecurePassword $securePassword
    return Add-EALabCredentialProviderMetadata -Credential $credential -ProviderName 'InlineConfig'
}

function ConvertFrom-EALabSecureString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [SecureString]$SecureStringValue
    )

    $bstr = [IntPtr]::Zero
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureStringValue)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Add-EALabCredentialProviderMetadata {
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $true)]
        [string]$ProviderName
    )

    $Credential | Add-Member -NotePropertyName Provider -NotePropertyValue $ProviderName -Force
    return $Credential
}

function Test-EALabCredentialManagerModuleAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return [bool](Get-Module -ListAvailable -Name 'CredentialManager')
}

function Initialize-EALabWinCredentialInterop {
    [CmdletBinding()]
    param()

    if ('EALab.WinCredentialReader' -as [type]) {
        return
    }

    $interopSource = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace EALab {
    public static class WinCredentialReader {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct CREDENTIAL {
            public int Flags;
            public int Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public int CredentialBlobSize;
            public IntPtr CredentialBlob;
            public int Persist;
            public int AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

        [DllImport("advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
        private static extern void CredFree([In] IntPtr cred);

        public static bool TryReadGenericCredential(string target, out string userName, out string password) {
            userName = null;
            password = null;

            IntPtr credentialPtr;
            if (!CredRead(target, 1, 0, out credentialPtr)) {
                return false;
            }

            try {
                var credential = (CREDENTIAL)Marshal.PtrToStructure(credentialPtr, typeof(CREDENTIAL));
                userName = credential.UserName;

                if (credential.CredentialBlob != IntPtr.Zero && credential.CredentialBlobSize > 0) {
                    var blobBytes = new byte[credential.CredentialBlobSize];
                    Marshal.Copy(credential.CredentialBlob, blobBytes, 0, credential.CredentialBlobSize);
                    password = Encoding.Unicode.GetString(blobBytes).TrimEnd('\0');
                }

                return true;
            } finally {
                CredFree(credentialPtr);
            }
        }
    }
}
"@

    Add-Type -TypeDefinition $interopSource -Language CSharp -ErrorAction Stop | Out-Null
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

    if (-not (Test-EALabCredentialManagerModuleAvailable)) {
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
    $credential = ConvertTo-EALabCredential -UserName ([string]$stored.UserName) -SecurePassword $securePassword
    return Add-EALabCredentialProviderMetadata -Credential $credential -ProviderName 'CredentialManager'
}

function Get-EALabCredentialFromWinCredNative {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialRef is a lookup key, not a secret value.')]
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CredentialRef
    )

    Initialize-EALabWinCredentialInterop

    $userName = ''
    $password = ''
    $found = [EALab.WinCredentialReader]::TryReadGenericCredential($CredentialRef, [ref]$userName, [ref]$password)
    if (-not $found) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($password)) {
        return $null
    }

    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
    $credential = ConvertTo-EALabCredential -UserName $userName -SecurePassword $securePassword
    return Add-EALabCredentialProviderMetadata -Credential $credential -ProviderName 'WinCredNative'
}

function Get-EALabCredentialFromCmdKey {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialRef is a lookup key, not a secret value.')]
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CredentialRef
    )

    $cmdKeyOutput = & cmdkey.exe "/list:$CredentialRef" 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $targetFound = $false
    foreach ($line in @($cmdKeyOutput)) {
        if ([string]$line -match '^\s*Target:\s*(.+)\s*$') {
            $parsedTarget = [string]$Matches[1]
            if ($parsedTarget -eq $CredentialRef) {
                $targetFound = $true
                break
            }
        }
    }

    if (-not $targetFound) {
        return $null
    }

    $nativeCredential = Get-EALabCredentialFromWinCredNative -CredentialRef $CredentialRef
    if ($null -eq $nativeCredential) {
        return $null
    }

    return Add-EALabCredentialProviderMetadata -Credential $nativeCredential -ProviderName 'CmdKey'
}

function Resolve-EALabCredentialRef {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialRef is a lookup key, not a secret value.')]
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CredentialRef
    )

    try {
        $fromCredentialManager = Get-EALabCredentialFromCredentialManager -CredentialRef $CredentialRef
        if ($null -ne $fromCredentialManager) {
            return $fromCredentialManager
        }
    }
    catch {
        # Move to fallback providers.
    }

    try {
        $fromCmdKey = Get-EALabCredentialFromCmdKey -CredentialRef $CredentialRef
        if ($null -ne $fromCmdKey) {
            return $fromCmdKey
        }
    }
    catch {
        # Move to final fallback provider.
    }

    try {
        return Get-EALabCredentialFromWinCredNative -CredentialRef $CredentialRef
    }
    catch {
        return $null
    }
}

function Set-EALabCredentialRef {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'Windows credential APIs require plaintext payload from secure source at write-time.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CredentialRef,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [SecureString]$SecurePassword,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Auto', 'CredentialManager', 'CmdKey')]
        [string]$Provider = 'Auto'
    )

    $plainPassword = ConvertFrom-EALabSecureString -SecureStringValue $SecurePassword
    try {
        if ($Provider -in @('Auto', 'CredentialManager') -and (Test-EALabCredentialManagerModuleAvailable)) {
            Import-Module CredentialManager -ErrorAction Stop | Out-Null
            $existing = Get-StoredCredential -Target $CredentialRef -ErrorAction SilentlyContinue
            if ($null -ne $existing) {
                Remove-StoredCredential -Target $CredentialRef -ErrorAction SilentlyContinue | Out-Null
            }

            New-StoredCredential -Target $CredentialRef -UserName $UserName -Password $plainPassword -Persist LocalMachine -ErrorAction Stop | Out-Null
            return [PSCustomObject]@{
                Ref      = $CredentialRef
                Provider = 'CredentialManager'
                Success  = $true
            }
        }

        if ($Provider -eq 'CredentialManager') {
            throw "CredentialManager module is not available. Unable to set credential ref '$CredentialRef' with provider CredentialManager."
        }

        $cmdOutput = & cmdkey.exe "/generic:$CredentialRef" "/user:$UserName" "/pass:$plainPassword" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "cmdkey failed to create credential '$CredentialRef'. Output: $($cmdOutput -join ' ')"
        }

        return [PSCustomObject]@{
            Ref      = $CredentialRef
            Provider = 'CmdKey'
            Success  = $true
        }
    }
    finally {
        $plainPassword = $null
    }
}

function Remove-EALabCredentialRef {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialRef is a lookup key, not a secret value.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CredentialRef
    )

    if (Test-EALabCredentialManagerModuleAvailable) {
        Import-Module CredentialManager -ErrorAction Stop | Out-Null
        Remove-StoredCredential -Target $CredentialRef -ErrorAction SilentlyContinue | Out-Null
    }

    $cmdOutput = & cmdkey.exe "/delete:$CredentialRef" 2>&1
    $removedByCmdKey = ($LASTEXITCODE -eq 0)
    return [PSCustomObject]@{
        Ref            = $CredentialRef
        Success        = $true
        RemovedByCmdKey = $removedByCmdKey
        Output         = ($cmdOutput -join [Environment]::NewLine)
    }
}

function Test-EALabCredentialRef {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialRef is a lookup key, not a secret value.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CredentialRef
    )

    $provider = ''
    $hasUserName = $false
    $hasPassword = $false
    $exists = $false

    $resolved = Resolve-EALabCredentialRef -CredentialRef $CredentialRef
    if ($null -ne $resolved) {
        $exists = $true
        $provider = if ($resolved.PSObject.Properties.Name -contains 'Provider') { [string]$resolved.Provider } else { 'Unknown' }
        $hasUserName = -not [string]::IsNullOrWhiteSpace([string]$resolved.UserName)
        $passwordText = ConvertFrom-EALabSecureString -SecureStringValue $resolved.Password
        $hasPassword = -not [string]::IsNullOrWhiteSpace($passwordText)
    }

    return [PSCustomObject]@{
        Ref              = $CredentialRef
        Exists           = $exists
        Provider         = $provider
        UserNamePresent  = $hasUserName
        PasswordPresent  = $hasPassword
    }
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
        [string]$InlineUserName,

        [Parameter(Mandatory = $false)]
        [string]$InlinePassword,

        [Parameter(Mandatory = $false)]
        [switch]$AllowPrompt
    )

    if (-not [string]::IsNullOrWhiteSpace($CredentialRef)) {
        try {
            $resolved = Resolve-EALabCredentialRef -CredentialRef $CredentialRef
            if ($null -ne $resolved) {
                return $resolved
            }
        }
        catch {
            # Fall through to prompt path when enabled.
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($InlineUserName) -and -not [string]::IsNullOrWhiteSpace($InlinePassword)) {
        $inlineCredential = ConvertTo-EALabCredentialFromPlainText -UserName $InlineUserName -Password $InlinePassword
        if ($null -ne $inlineCredential) {
            return $inlineCredential
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
                throw "Credential '$PromptLabel' could not be resolved in this non-interactive session. Configure credentials.*Ref in lab config and store matching values in Windows Credential Manager, or set inline credentials.*User/*Password in lab config. Current reference: '$displayRef'."
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
    $localAdminUser = if ($credentialConfig.PSObject.Properties.Name -contains 'localAdminUser') { [string]$credentialConfig.localAdminUser } else { '' }
    $localAdminPassword = if ($credentialConfig.PSObject.Properties.Name -contains 'localAdminPassword') { [string]$credentialConfig.localAdminPassword } else { '' }
    $domainAdminUser = if ($credentialConfig.PSObject.Properties.Name -contains 'domainAdminUser') { [string]$credentialConfig.domainAdminUser } else { '' }
    $domainAdminPassword = if ($credentialConfig.PSObject.Properties.Name -contains 'domainAdminPassword') { [string]$credentialConfig.domainAdminPassword } else { '' }
    $dsrmUser = if ($credentialConfig.PSObject.Properties.Name -contains 'dsrmUser') { [string]$credentialConfig.dsrmUser } else { '' }
    if ([string]::IsNullOrWhiteSpace($dsrmUser)) {
        $dsrmUser = 'DSRM'
    }
    $dsrmPassword = if ($credentialConfig.PSObject.Properties.Name -contains 'dsrmPassword') { [string]$credentialConfig.dsrmPassword } else { '' }

    return [PSCustomObject]@{
        LocalAdmin = Get-EALabCredential -CredentialRef $localAdminRef -PromptLabel 'Local admin credential' -InlineUserName $localAdminUser -InlinePassword $localAdminPassword -AllowPrompt:$AllowPrompt
        DomainAdmin = if (-not [string]::IsNullOrWhiteSpace($domainAdminRef) -or (-not [string]::IsNullOrWhiteSpace($domainAdminUser) -and -not [string]::IsNullOrWhiteSpace($domainAdminPassword))) {
            Get-EALabCredential -CredentialRef $domainAdminRef -PromptLabel 'Domain admin credential' -InlineUserName $domainAdminUser -InlinePassword $domainAdminPassword -AllowPrompt:$AllowPrompt
        } else {
            $null
        }
        Dsrm = if (-not [string]::IsNullOrWhiteSpace($dsrmRef) -or -not [string]::IsNullOrWhiteSpace($dsrmPassword)) {
            Get-EALabCredential -CredentialRef $dsrmRef -PromptLabel 'DSRM credential' -InlineUserName $dsrmUser -InlinePassword $dsrmPassword -AllowPrompt:$AllowPrompt
        } else {
            $null
        }
    }
}

function Test-EALabCredentialManagerSupport {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if (Test-EALabCredentialManagerModuleAvailable) {
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
    'Resolve-EALabCredentialRef',
    'Set-EALabCredentialRef',
    'Remove-EALabCredentialRef',
    'Test-EALabCredentialRef',
    'Test-EALabCredentialManagerSupport'
)
