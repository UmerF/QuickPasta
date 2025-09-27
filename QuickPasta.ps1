param(
  [Parameter(Mandatory = $true)][string]$Profile,
  [Parameter(Mandatory = $true)][string]$Target
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# =========================
# Logging (portable, rotated)
# =========================
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$log       = Join-Path $scriptDir 'quickpasta.log'

# $false = errors only (recommended), $true = info + errors
$LogInfoEnabled = $false
# Max log size before rotation (bytes); set 0 to disable rotation
$MaxLogBytes = 512KB

New-Item -ItemType Directory -Path $scriptDir -ErrorAction SilentlyContinue | Out-Null

function Rotate-Log {
  if ($MaxLogBytes -gt 0 -and (Test-Path -LiteralPath $log)) {
    try {
      $len = (Get-Item -LiteralPath $log).Length
      if ($len -gt $MaxLogBytes) {
        $bak   = "$log.bak"
        $lines = Get-Content -LiteralPath $log -Tail 400 -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $bak -Value $lines -Encoding UTF8
        Move-Item -LiteralPath $bak -Destination $log -Force
      }
    } catch {}
  }
}
function Write-Log([string]$msg, [string]$level = 'INFO') {
  if ($level -eq 'INFO' -and -not $LogInfoEnabled) { return }
  $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg
  Add-Content -LiteralPath $log -Value $line
}
function LogInfo([string]$msg)  { Write-Log $msg 'INFO'  }
function LogError([string]$msg) { Write-Log $msg 'ERROR' }

Rotate-Log

# =========
# Helpers
# =========
function Get-TargetFolder([string]$path) {
  $item = Get-Item -LiteralPath $path -ErrorAction Stop
  if ($item.PSIsContainer) { $item.FullName } else { $item.DirectoryName }
}

function Test-ZipUrl([string]$s) { ($s -match '^https?://' -and $s -match '\.zip($|\?)') }

function Invoke-DownloadAndExtractZip([string]$url) {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
  $workRoot = Join-Path $env:TEMP ('QuickPasta_' + [guid]::NewGuid().ToString('N'))
  $zipPath  = Join-Path $workRoot 'payload.zip'
  $extract  = Join-Path $workRoot 'extract'
  New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
  New-Item -ItemType Directory -Path $extract  -Force | Out-Null

  LogInfo "Downloading ZIP: $url"
  Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
  LogInfo "Downloaded: $zipPath"

  Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force
  LogInfo "Extracted to: $extract"
  @{ Source = $extract; Work = $workRoot }
}

function Remove-EmptyDirs([string]$root) {
  try {
    Get-ChildItem -LiteralPath $root -Directory -Recurse -Force |
      Where-Object { ($_.GetFileSystemInfos().Count -eq 0) } |
      ForEach-Object {
        try {
          $_.Attributes = 'Normal'
          Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        } catch {}
      }
  } catch {}
}

function Invoke-ApplyRenames([string]$root, [object]$rules) {
  if (-not $rules) { return }

  # Normalize to a collection
  if ($rules -isnot [System.Collections.IEnumerable] -or $rules -is [string]) {
    $rules = @($rules)
  }

  # Track base folders that should be removed when empty (e.g., "shaders/** -> @delete")
  $deletedBaseDirs = New-Object 'System.Collections.Generic.HashSet[string]'

  foreach ($r in $rules) {
    $from = [string]$r.from
    $to   = [string]$r.to
    if (-not $from -or -not $to) { continue }

    # Normalize slashes
    $fromNorm = ($from -replace '\\', '/').Trim()
    $toNorm   = ($to   -replace '\\', '/').Trim()

    $isRecursive = ($fromNorm -match '\*\*')

    # Build match list
    $matches = @()
    if ($isRecursive) {
      # Convert ** to * for -like over relative paths
      $likePat = ($fromNorm -replace '\*\*', '*')
      $all = Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue
      foreach ($f in $all) {
        $rel = $f.FullName.Substring($root.Length).TrimStart('\','/') -replace '\\','/'
        if ($rel -like $likePat) { $matches += ,$f }
      }
    } else {
      # Non-recursive: only direct children in the directory part of the pattern
      $fromPath  = Join-Path $root $fromNorm
      $searchDir = Split-Path $fromPath -Parent
      $leafPat   = Split-Path $fromPath -Leaf
      if (-not (Test-Path -LiteralPath $searchDir -PathType Container)) { continue }
      $matches = Get-ChildItem -Path $searchDir -Filter $leafPat -File -Force -ErrorAction SilentlyContinue
    }

    # --- Delete action ---
    if ($toNorm -ieq '@delete') {
      foreach ($f in $matches) {
        try {
          $f.Attributes = 'Normal'
          Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
        } catch {
          Write-Log ("Delete failed '{0}': {1}" -f $f.FullName, $_.Exception.Message) 'ERROR'
        }
      }

      # If the rule is clearly of the form "<base>/**", remember <base> to prune later
      $baseCandidate = ($fromNorm -replace '/\*\*.*$','').Trim()
      if ($baseCandidate -and -not ($baseCandidate.Contains('/') -or $baseCandidate.Contains('*'))) {
        [void]$deletedBaseDirs.Add($baseCandidate)
      }
      continue
    }

    # Destination mode
    $rhsIsFolder = $toNorm.EndsWith('/') -or $toNorm.EndsWith('\') `
                   -or (Test-Path -LiteralPath (Join-Path $root $toNorm) -PathType Container)
    $rhsHasSlash = $toNorm.Contains('/') -or $toNorm.Contains('\')
    $lhsHasSlash = $fromNorm.Contains('/')

    foreach ($f in $matches) {
      try {
        $dest = $null

        if ($rhsIsFolder) {
          # Move to folder (create if missing), preserve filename
          $destDir = Join-Path $root ($toNorm.TrimEnd('/','\'))
          if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
          }
          $dest = Join-Path $destDir $f.Name
        }
        elseif ($rhsHasSlash -or $lhsHasSlash) {
          # Treat RHS (or bare RHS with LHS path) as a relative path under target root
          $dest = Join-Path $root $toNorm
          $destParent = Split-Path $dest -Parent
          if ($destParent -and -not (Test-Path -LiteralPath $destParent -PathType Container)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
          }
        }
        else {
          # Simple rename in place
          $dest = Join-Path $f.DirectoryName $toNorm
        }

        if (Test-Path -LiteralPath $dest) {
          (Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue).Attributes = 'Normal'
          Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $f.FullName -Destination $dest -Force
      }
      catch {
        Write-Log ("Rename/move failed for '{0}' -> '{1}': {2}" -f $f.FullName, $toNorm, $_.Exception.Message) 'ERROR'
      }
    }
  }

  # Generic empty-dir pruning
  Remove-EmptyDirs -root $root

  # Remove any remembered base folders if they ended up empty
  foreach ($baseName in $deletedBaseDirs) {
    try {
      if ([string]::IsNullOrWhiteSpace($baseName)) { continue }
      $basePath = Join-Path $root $baseName
      if (Test-Path -LiteralPath $basePath -PathType Container) {
        if ((Get-ChildItem -LiteralPath $basePath -Force | Measure-Object).Count -eq 0) {
          (Get-Item -LiteralPath $basePath).Attributes = 'Normal'
          Remove-Item -LiteralPath $basePath -Force -ErrorAction SilentlyContinue
        }
      }
    } catch {}
  }
}

function Normalize([string]$s) { ($s -replace '\s+',' ').Trim() }

# ========
# Main
# ========
try {
  LogInfo '---- QuickPasta run start ----'
  LogInfo "Incoming Profile='$Profile' Target='$Target'"

  $configPath = Join-Path $scriptDir 'profiles.json'
  if (!(Test-Path -LiteralPath $configPath)) { throw "Missing $configPath" }

  $json        = Get-Content -LiteralPath $configPath -Raw
  $profilesObj = $json | ConvertFrom-Json

  # Build name -> value map robustly
  $map = @{}; foreach ($p in $profilesObj.PSObject.Properties) { $map[$p.Name] = $p.Value }

  # Match requested profile (exact, then normalized)
  $incoming   = $Profile
  $names      = $map.Keys
  $chosen     = $names | Where-Object { $_ -ceq $incoming }
  if (-not $chosen) {
    $normIn  = Normalize $incoming
    $chosen  = $names | Where-Object { (Normalize $_) -ceq $normIn }
  }
  $chosenName = ($chosen | Select-Object -First 1)
  if ([string]::IsNullOrEmpty($chosenName)) { throw "Profile '$incoming' not found. Available: $($names -join ', ')" }
  LogInfo "Matched: '$chosenName'"

  # Resolve entry (string OR object {source, renames})
  $entry = $map[$chosenName]
  if ($null -eq $entry) { throw "Profile '$chosenName' not found in map." }

  $sourceSpec  = $null
  $renameRules = $null
  if ($entry -is [string]) {
    $sourceSpec = $entry
  }
  elseif ($entry -is [System.Management.Automation.PSCustomObject]) {
    $sourceSpec  = [string]($entry | Select-Object -ExpandProperty source -ErrorAction SilentlyContinue)
    if (-not $sourceSpec) { $sourceSpec = [string]($entry | Select-Object -ExpandProperty path -ErrorAction SilentlyContinue) }
    $renameRules =  ($entry | Select-Object -ExpandProperty renames -ErrorAction SilentlyContinue)
  }
  else {
    $sourceSpec = [string]$entry
  }
  if (-not $sourceSpec) { throw "Profile '$chosenName' has no 'source' defined." }

  # Resolve target
  $targetPath = Get-TargetFolder -path $Target

  # Prepare source (zip vs. folder)
  $tempWork   = $null
  $sourcePath = $null
  if (Test-ZipUrl $sourceSpec) {
    $tempWork   = Invoke-DownloadAndExtractZip $sourceSpec
    $sourcePath = $tempWork.Source
  } else {
    $sourcePath = $sourceSpec
  }
  if (!(Test-Path -LiteralPath $sourcePath)) { throw "Source not found: $sourcePath" }

  # Copy contents into target (never mutate source)
  $itemsToCopy = @(Get-ChildItem -LiteralPath $sourcePath -Force)
  if ($itemsToCopy.Count -eq 0) {
    LogInfo "Source empty: $sourcePath (nothing to copy)"
  }
  else {
    foreach ($item in $itemsToCopy) {
      Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Recurse -Force
    }
    LogInfo "Copy: '$sourcePath' -> '$targetPath' (done)"
  }

  # Apply renames only in destination tree
  Invoke-ApplyRenames -root $targetPath -rules $renameRules
}
catch {
  LogError ($_.Exception.Message)
  exit 1
}
finally {
  if ($tempWork -and (Test-Path -LiteralPath $tempWork.Work)) {
    Remove-Item -LiteralPath $tempWork.Work -Recurse -Force -ErrorAction SilentlyContinue
    LogInfo "Cleaned temp: $($tempWork.Work)"
  }
  LogInfo '---- QuickPasta run end ----'
}
