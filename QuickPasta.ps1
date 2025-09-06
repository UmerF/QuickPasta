# Z:\Game Tools\.QuickPasta\QuickPasta.ps1
param(
  [Parameter(Mandatory=$true)][string]$Profile,
  [Parameter(Mandatory=$true)][string]$Target
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Resolve-TargetFolder([string]$path) {
  $item = Get-Item -LiteralPath $path -ErrorAction Stop
  if ($item.PSIsContainer) { return $item.FullName } else { return $item.DirectoryName }
}

function Is-ZipUrl([string]$s) {
  return ($s -match '^https?://' -and $s -match '\.zip($|\?)')
}

function Download-And-ExtractZip([string]$url) {
  # Ensure TLS 1.2 for modern HTTPS
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

  $workRoot = Join-Path $env:TEMP ("QuickPasta_" + [guid]::NewGuid().ToString("N"))
  $zipPath  = Join-Path $workRoot "payload.zip"
  $extract  = Join-Path $workRoot "extract"
  New-Item -ItemType Directory -Path $workRoot, $extract | Out-Null

  Write-Host "QuickPasta: Downloading ZIP..."
  Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

  Write-Host "QuickPasta: Extracting ZIP..."
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force

  # Return extraction folder and work root for later cleanup
  return @{ Source=$extract; Work=$workRoot }
}

try {
  # Resolve target
  $targetPath = Resolve-TargetFolder -path $Target

  # Load profiles
  $configPath = "Z:\Game Tools\.QuickPasta\profiles.json"
  if (!(Test-Path -LiteralPath $configPath)) { throw "Missing $configPath" }
  $profiles = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  if (-not $profiles.$Profile) { throw "Profile '$Profile' not found in profiles.json" }

  $sourceSpec = [string]$profiles.$Profile
  $tempWork = $null
  if (Is-ZipUrl $sourceSpec) {
    $tempWork = Download-And-ExtractZip $sourceSpec
    $sourcePath = $tempWork.Source
  } else {
    $sourcePath = $sourceSpec
  }

  if (!(Test-Path -LiteralPath $sourcePath)) { throw "Source not found: $sourcePath" }

  Write-Host "QuickPasta: Copying from '$sourcePath' to '$targetPath'..."
  Copy-Item -Path (Join-Path $sourcePath '*') -Destination $targetPath -Recurse -Force

  Write-Host "QuickPasta: Done."
}
catch {
  [console]::Error.WriteLine("QuickPasta: " + $_.Exception.Message)
  Read-Host "Press Enter to close"
  exit 1
}
finally {
  # Clean temp if we downloaded
  if ($tempWork -and (Test-Path -LiteralPath $tempWork.Work)) {
    try { Remove-Item -LiteralPath $tempWork.Work -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  }
}
# Uncomment if you want to pause on success during testing:
# Read-Host "Press Enter to close"
