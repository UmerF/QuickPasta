# Z:\Game Tools\.QuickPasta\QuickPasta.ps1
param(
  [Parameter(Mandatory=$true)][string]$Profile,
  [Parameter(Mandatory=$true)][string]$Target
)

$ErrorActionPreference = "Stop"

# Resolve target (folder to receive files)
try {
  $item = Get-Item -LiteralPath $Target -ErrorAction Stop
  $targetPath = if ($item.PSIsContainer) { $item.FullName } else { $item.DirectoryName }
} catch {
  [console]::Error.WriteLine("QuickPasta: Target does not exist: $Target")
  Read-Host "Press Enter to close"
  exit 1
}

# Load profile map
$configPath = "Z:\Game Tools\.QuickPasta\profiles.json"
if (!(Test-Path -LiteralPath $configPath)) {
  [console]::Error.WriteLine("QuickPasta: Missing $configPath")
  Read-Host "Press Enter to close"
  exit 1
}

$profiles = Get-Content -LiteralPath $configPath | ConvertFrom-Json
if (-not $profiles.$Profile) {
  [console]::Error.WriteLine("QuickPasta: Profile '$Profile' not found in profiles.json")
  Read-Host "Press Enter to close"
  exit 1
}

$sourcePath = $profiles.$Profile
if (!(Test-Path -LiteralPath $sourcePath)) {
  [console]::Error.WriteLine("QuickPasta: Source not found: $sourcePath")
  Read-Host "Press Enter to close"
  exit 1
}

Write-Host "QuickPasta: Copying from '$sourcePath' to '$targetPath'..."

# IMPORTANT FIX: use -Path (wildcards allowed), not -LiteralPath
Copy-Item -Path (Join-Path $sourcePath '*') -Destination $targetPath -Recurse -Force

Write-Host "QuickPasta: Done."
# Comment the next line if you want the window to auto-close on success
# Read-Host "Press Enter to close"
