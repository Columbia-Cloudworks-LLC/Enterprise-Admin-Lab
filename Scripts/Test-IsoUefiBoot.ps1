# Quick ISO UEFI boot file check for diagnostics
param([string]$IsoPath)
if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) { Write-Output "ISO not found: $IsoPath"; exit 1 }
$img = Mount-DiskImage -ImagePath $IsoPath -PassThru
$vol = $img | Get-Volume
$driveLetter = $vol.DriveLetter + ":\"
$efiPath = Join-Path $driveLetter "EFI\BOOT"
if (Test-Path -LiteralPath $efiPath) {
    Get-ChildItem -LiteralPath $efiPath | Select-Object Name
} else {
    Write-Output "EFI\BOOT not found - ISO may not support UEFI boot"
}
Dismount-DiskImage -ImagePath $IsoPath | Out-Null
