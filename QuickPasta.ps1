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


function Test-Url([string]$s) { $s -match '^https?://\S+' }




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

function Invoke-DownloadFile([string]$url) {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
  $workRoot = Join-Path $env:TEMP ('QuickPasta_' + [guid]::NewGuid().ToString('N'))
  $downloadDir = Join-Path $workRoot 'download'
  $fileName = [System.IO.Path]::GetFileName(($url -split '\?')[0])
  if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName = 'payload' }
  $filePath = Join-Path $downloadDir $fileName
  New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
  New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
  LogInfo "Downloading file: $url"
  Invoke-WebRequest -Uri $url -OutFile $filePath -UseBasicParsing
  LogInfo "Downloaded file to: $filePath"
  @{ Source = $downloadDir; Work = $workRoot; File = $filePath }
}

function Find-SevenZipExe {
  $candidates = @()
  if ($env:ProgramFiles) { $candidates += Join-Path $env:ProgramFiles '7-Zip\7z.exe' }
  if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe' }
  $candidates += Join-Path $scriptDir '7z.exe'
  $candidates += Join-Path $scriptDir '7za.exe'
  $candidates += Join-Path $scriptDir '7Zip\7z.exe'
  $candidates += Join-Path $scriptDir '7Zip\7za.exe'

  foreach ($dir in ($env:PATH -split ';')) {
    if ([string]::IsNullOrWhiteSpace($dir)) { continue }
    try { $candidates += Join-Path $dir '7z.exe' } catch {}
  }
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  return $null
}


function Ensure-SevenZipPortable {
  $portableDir = Join-Path $scriptDir '7Zip'
  $portableExe = Join-Path $portableDir '7za.exe'
  $existing = Find-SevenZipExe
  if ($existing) { return $existing }
  if (Test-Path -LiteralPath $portableExe) { return $portableExe }

  $downloadUrl = 'https://www.7-zip.org/a/7za920.zip'
  $archivePath = Join-Path $portableDir '7za.zip'

  try {
    New-Item -ItemType Directory -Path $portableDir -Force | Out-Null
    LogInfo "Downloading portable 7-Zip"
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop } catch {}

    if (Test-Path -LiteralPath $portableDir) {
      Get-ChildItem -LiteralPath $portableDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '7z*.exe' -or $_.Name -like '7z*.dll' } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }

    [System.IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $portableDir)

    $exeTargets = Get-ChildItem -LiteralPath $portableDir -Recurse -Filter '7z*.exe' -ErrorAction SilentlyContinue
    foreach ($exe in $exeTargets) {
      if ($exe.DirectoryName -ne $portableDir) {
        $dest = Join-Path $portableDir $exe.Name
        try {
          if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
          Move-Item -LiteralPath $exe.FullName -Destination $dest -Force
        } catch {}
      }
    }

    $dllTargets = Get-ChildItem -LiteralPath $portableDir -Recurse -Filter '7z*.dll' -ErrorAction SilentlyContinue
    foreach ($dll in $dllTargets) {
      if ($dll.DirectoryName -ne $portableDir) {
        $destDll = Join-Path $portableDir $dll.Name
        try {
          if (Test-Path -LiteralPath $destDll) { Remove-Item -LiteralPath $destDll -Force -ErrorAction SilentlyContinue }
          Move-Item -LiteralPath $dll.FullName -Destination $destDll -Force
        } catch {}
      }
    }

    $candidate = Find-SevenZipExe
    if ($candidate) {
      LogInfo "Portable 7-Zip ready"
      return $candidate
    }
  }
  catch {
    LogInfo ("Portable 7-Zip download failed: {0}" -f $_.Exception.Message)
  }
  finally {
    if (Test-Path -LiteralPath $archivePath) {
      Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
    }
  }
  return $null
}

function Invoke-IncludeRules([string]$sourceRoot, [string]$targetRoot, [object[]]$includeRules) {
  if (-not $includeRules -or $includeRules.Count -eq 0) { return }

  foreach ($rule in $includeRules) {
    $targetRaw = [string]$rule.to
    if ([string]::IsNullOrWhiteSpace($targetRaw)) { continue }

    $targetNorm = ($targetRaw -replace '\\','/').Trim().TrimStart('/')
    $sourceNorm = $null

    foreach ($propName in 'source','include','path','fromPath') {
      try {
        $candidate = [string]($rule | Select-Object -ExpandProperty $propName -ErrorAction Stop)
        if ($candidate) { $sourceNorm = $candidate; break }
      }
      catch {}
    }

    if (-not $sourceNorm) { $sourceNorm = $targetNorm }

    $sourceNorm = ($sourceNorm -replace '\\','/').Trim().TrimStart('/')
    $sourcePattern = ($sourceNorm -replace '/', '\\')
    $sourceFull    = Join-Path $sourceRoot $sourcePattern

    $matches = @()
    if ($sourceNorm -match '[\*\?]') {
      $sourceDir = Split-Path $sourceFull -Parent
      if (-not $sourceDir) { $sourceDir = $sourceRoot }
      $leaf = Split-Path $sourceFull -Leaf
      $matches = @(Get-ChildItem -Path $sourceDir -Filter $leaf -File -Force -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending)
    }
    elseif (Test-Path -LiteralPath $sourceFull -PathType Leaf) {
      $matches = ,(Get-Item -LiteralPath $sourceFull)
    }

    if ($matches.Count -eq 0) {
      LogError ("Include source not found: {0}" -f (Join-Path $sourceRoot $sourceNorm))
      continue
    }

    $chosen   = $matches[0]
    $destFull = Join-Path $targetRoot ($targetNorm -replace '/', '\\')
    $destDir  = Split-Path $destFull -Parent
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
      New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    try {
      Copy-Item -LiteralPath $chosen.FullName -Destination $destFull -Force
      LogInfo ("Include copy: '{0}' -> '{1}'" -f $chosen.FullName, $destFull)
    }
    catch {
      LogError ("Include copy failed '{0}' -> '{1}': {2}" -f $chosen.FullName, $destFull, $_.Exception.Message)
    }
  }
}
function Invoke-SevenZipExtract([string]$SevenZipPath, [string]$FilePath, [string]$Destination) {
  try {
    if (Test-Path -LiteralPath $Destination) {
      Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $SevenZipPath
    $psi.Arguments = "x -bd -y -o`"$Destination`" `"$FilePath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    return ($proc.ExitCode -eq 0)
  } catch {
    return $false
  }
}


function Try-ExtractZipSfx([string]$filePath, [string]$extractDir, [string]$workRoot) {
  $tempZip = $null
  try {
    if (-not ('QuickPasta.ZipSfxHelper' -as [type])) {
      try {
        Add-Type -TypeDefinition @"
using System;
using System.IO;
namespace QuickPasta {
  public static class ZipSfxHelper {
    private static readonly byte[] Signature = new byte[] { 0x50, 0x4B, 0x03, 0x04 };
    public static bool CopyTailTo(string source, string destination) {
      using (var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read)) {
        int match = 0;
        int b;
        while ((b = input.ReadByte()) != -1) {
          if (b == Signature[match]) {
            match++;
            if (match == Signature.Length) {
              long start = input.Position - Signature.Length;
              input.Position = start;
              using (var output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None)) {
                input.CopyTo(output);
              }
              return true;
            }
          }
          else {
            match = (b == Signature[0]) ? 1 : 0;
          }
        }
      }
      return false;
    }
  }
}
"@ -Language CSharp
      }
      catch {
        LogInfo ("Failed to prepare SFX helper: {0}" -f $_.Exception.Message)
        return $null
      }
    }

    $tempZip = Join-Path $workRoot 'payload_sfx.zip'
    if (-not [QuickPasta.ZipSfxHelper]::CopyTailTo($filePath, $tempZip)) {
      return $null
    }

    if (Test-Path -LiteralPath $extractDir) {
      Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop } catch {}
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $extractDir)
    LogInfo "Extracted file to: $extractDir (SFX zip tail)"
    return $extractDir
  }
  catch {
    LogInfo ("SFX extraction failed for {0}: {1}" -f $filePath, $_.Exception.Message)
    return $null
  }
  finally {
    if ($tempZip -and (Test-Path -LiteralPath $tempZip)) {
      Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    }
  }
}

function Try-ExtractDownload([string]$filePath, [string]$workRoot) {
  $extractDir = Join-Path $workRoot 'extract'
  $zipMessage = $null
  try {
    if (Test-Path -LiteralPath $extractDir) {
      Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop } catch {}
    [System.IO.Compression.ZipFile]::ExtractToDirectory($filePath, $extractDir)
    LogInfo "Extracted file to: $extractDir"
    return $extractDir
  }
  catch {
    $zipMessage = $_.Exception.Message
  }
  try { if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
  $sfxResult = Try-ExtractZipSfx -filePath $filePath -extractDir $extractDir -workRoot $workRoot
  if ($sfxResult) { return $sfxResult }
  $sevenZip = Find-SevenZipExe
  if (-not $sevenZip) { $sevenZip = Ensure-SevenZipPortable }
  if ($sevenZip) {
    if (Invoke-SevenZipExtract -SevenZipPath $sevenZip -FilePath $filePath -Destination $extractDir) {
      LogInfo "Extracted file to: $extractDir using 7-Zip ($sevenZip)"
      return $extractDir
    }
  } else {
    LogInfo "7z.exe not found while trying to extract $filePath; leaving original file"
  }
  if (-not $zipMessage) { $zipMessage = 'archive format not supported' }
  LogInfo ("Extraction skipped for {0}: {1}" -f $filePath, $zipMessage)
  return $null
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
  if ($rules -is [System.Management.Automation.PSCustomObject]) {
    $rules = @($rules)
  }
  elseif ($rules -isnot [System.Collections.IEnumerable] -or $rules -is [string]) {
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
  $extractFlag = $false
  $includeRules = @()
  if ($entry -is [string]) {
    $sourceSpec = $entry
  }
  elseif ($entry -is [System.Management.Automation.PSCustomObject]) {
    $sourceSpec  = [string]($entry | Select-Object -ExpandProperty source -ErrorAction SilentlyContinue)
    if (-not $sourceSpec) { $sourceSpec = [string]($entry | Select-Object -ExpandProperty path -ErrorAction SilentlyContinue) }
    $renameRules =  ($entry | Select-Object -ExpandProperty renames -ErrorAction SilentlyContinue)
    if ($renameRules -ne $null) {
      if ($renameRules -is [System.Collections.IEnumerable] -and $renameRules -isnot [string]) {
        $renameRules = @($renameRules)
      }
      else {
        $renameRules = @($renameRules)
      }
      $includeRules = @($renameRules | Where-Object { ([string]$_.from).Trim() -ieq '@include' })
      if ($includeRules.Count -gt 0) {
        $renameRules = @($renameRules | Where-Object { ([string]$_.from).Trim() -ine '@include' })
      }
    }
    $extractValue = ($entry | Select-Object -ExpandProperty extract -ErrorAction SilentlyContinue)
    if ($null -ne $extractValue) {
      try { $extractFlag = [System.Convert]::ToBoolean($extractValue) } catch {}
    }
  }
  else {
    $sourceSpec = [string]$entry
  }
  if (-not $sourceSpec) { throw "Profile '$chosenName' has no 'source' defined." }

  # Resolve target
  $targetPath = Get-TargetFolder -path $Target

  # Prepare source (URL vs. folder)
  $tempWork   = $null
  $sourcePath = $null
  if (Test-Url $sourceSpec) {
    if (Test-ZipUrl $sourceSpec) {
      $tempWork = Invoke-DownloadAndExtractZip $sourceSpec
    } else {
      $tempWork = Invoke-DownloadFile $sourceSpec
      if ($extractFlag -and $tempWork.File) {
        $extracted = Try-ExtractDownload $tempWork.File $tempWork.Work
        if ($extracted) { $tempWork['Source'] = $extracted }
      }
    }
    $sourcePath = $tempWork.Source
  } else {
    $sourcePath = $sourceSpec
  }
  if (!(Test-Path -LiteralPath $sourcePath)) { throw "Source not found: $sourcePath" }

  $includeOnly = ($includeRules.Count -gt 0 -and ($null -eq $renameRules -or $renameRules.Count -eq 0))

  # Copy contents into target (never mutate source)
  if (-not $includeOnly) {
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
  }
  else {
    LogInfo "Include-only profile: skipping bulk copy from '$sourcePath'"
  }

  if ($includeRules.Count -gt 0) {
    Invoke-IncludeRules -sourceRoot $sourcePath -targetRoot $targetPath -includeRules $includeRules
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


