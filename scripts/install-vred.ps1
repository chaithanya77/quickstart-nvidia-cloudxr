<#PSScriptInfo
.VERSION 1.0
.GUID 99043890-70d0-4691-af9f-8a315ae9deef
.AUTHOR norman.geiersbach@autodesk.com
.COMPANYNAME Autodesk
.COPYRIGHT Autodesk, Inc. All Rights Reserved.
#>

<#
.DESCRIPTION
 A script to install SteamVR and VRED Core on an AWS EC2 Windows instance.
#>
Param (
  [parameter(Mandatory=$true, HelpMessage="The optional AWS S3 bucket.")]
  [String]
  $S3Bucket,
  [parameter(Mandatory=$true, HelpMessage="The name of the vred core installer.")]
  [String]
  $KeyPrefix,
  [parameter(Mandatory=$false, HelpMessage="The AWS access key for the user account.")]
  [String]
  $AccessKey,
  [parameter(Mandatory=$false, HelpMessage="The AWS secret key for the user account.")]
  [String]
  $SecretKey
)

# Disable Windows Defender Realtime Protection to speed up the installation
Set-MpPreference -DisableRealtimeMonitoring $true

Import-Module -Name C:\cfn\scripts\vred-library.psm1 -Force

# Create tempoary folder
$tempPath = New-TempFolder

# Copy installer from AWS S3 bucket to temporary directory
# Find documentation here: https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/AmazonS3.html
Write-Output "Copy installer files from AWS S3 bucket '$S3Bucket' to local temp folder '$tempPath'"
if (![string]::IsNullOrWhiteSpace($AccessKey) -or ![string]::IsNullOrWhiteSpace($SecretKey)) {
  # Copy installer files
  Copy-S3Object -BucketName $S3Bucket -KeyPrefix $KeyPrefix -LocalFolder $tempPath -AccessKey $AccessKey -SecretKey $SecretKey
} else {
  # Copy installer files
  Copy-S3Object -BucketName $S3Bucket -KeyPrefix $KeyPrefix -LocalFolder $tempPath
}

# Find sfx files of VRED Core installer and sort them alphabetically
# Expects Autodesk sfx installer files e.g. Autodesk_VREDCOR_2023_0_0_Enu_Win_64bit_dlm_001_002.sfx.exe
$vredInstArchives = @(Get-Childitem -Path $tempPath -Filter "Autodesk_VREDCOR*.sfx.exe" | ForEach-Object {"$($_.FullName)"} | Sort-Object)
if ($vredInstArchives.count -eq 0) {
  Write-Output "No Autodesk VRED Core Installer archives found."
  exit 1
}

# Extract sfx of VRED Core installer
$vredInstSfx = $vredInstArchives[0]
Write-Output "Extract VRED Core installer '$vredInstSfx'."
Start-Process -FilePath $vredInstSfx -ArgumentList "-suppresslaunch -d C:\Autodesk" -Wait

# Find extraction folder
# Expects Autodesk extracted installer folder e.g. Autodesk_VREDCOR_2023_0_0_Enu_Win_64bit_dlm
$vredInstDirs = @(Get-Childitem -Path "C:\Autodesk" -Filter "Autodesk_VREDCOR*" -Directory | ForEach-Object {"$($_.FullName)"})
if ($vredInstDirs.count -eq 0) {
  Write-Output "No Autodesk VRED Core Installer directories found."
  exit 1
}

# Remove the unnecessary AdSSO package from the installer as a workaround to fix an installation failure that occurs from time to time
try {
  $manifestFile = Join-Path $vredInstDirs[0] "manifest\app.vredcore.xml"
  $packageRegex = '<Package.+?(?=name="AdSSO").+?(?=/>)/>'
  (Get-Content $manifestFile) -replace $packageRegex, '' | Set-Content $manifestFile
} catch {
  Write-Output "Error removing AdSSO package from VRED Core installer."
}

# Start installation of VRED Core
$vredInstPath = Join-Path $vredInstDirs[0] "deploymentInstall.bat"
Write-Output "Run VRED Core installer '$vredInstPath'."
Start-Process -FilePath $vredInstPath -Wait
Write-Output "VRED Core installation completed."

# Extract SteamVR files
$steamZipPath = Join-Path $tempPath "SteamVR.zip"
$steamInstPath = Join-Path $tempPath "SteamVR"
Expand-Archive -LiteralPath $steamZipPath -DestinationPath $steamInstPath

# Start SteamVR
# https://vrcollab.com/help/install-steamvr-in-an-enterprise-or-government-use-environment/
$steamVRPath = Join-Path $steamInstPath "bin\win64\vrstartup.exe"
Start-Process -FilePath $steamVRPath
Write-Output "SteamVR started."

# Re-enable Windows Defender Realtime Protection to speed up the installation
Set-MpPreference -DisableRealtimeMonitoring $false