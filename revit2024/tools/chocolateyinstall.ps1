$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $toolsDir 'helpers.ps1')

# Official Autodesk download for Revit 2024: five self-extracting parts.
# Each part is verified against its SHA-256 below before anything runs.
$baseUrl = 'https://efulfillment.autodesk.com/NetSWDLD/2024/RVT/E7F68AA6-4954-3ACE-8543-D2FCC9B0A356/SFX'
$parts = [ordered]@{
  'Revit_2024_G1_Win_64bit_dlm_001_005.sfx.exe' = '535C80C98409879AAAACE1CDC20FAFD43E9D8218CA3008CDD7067FDADFBF8C54'
  'Revit_2024_G1_Win_64bit_dlm_002_005.sfx.exe' = '6D138CEBC7012B156A9142B47A91ED6283290935EEFC41FE48DC47FAB5AD98B1'
  'Revit_2024_G1_Win_64bit_dlm_003_005.sfx.exe' = '6238899E5E24194BAAB927816944B6B788E932F8B2CF40966FAAD447714AA9D0'
  'Revit_2024_G1_Win_64bit_dlm_004_005.sfx.exe' = 'F6C15EE21EA758A602FFB25E25C9850500A0BD07337C6F57EDCB72A16D4A66CE'
  'Revit_2024_G1_Win_64bit_dlm_005_005.sfx.exe' = 'FBCCF82214E409CC6B07F0A92BE38E167030F36791D239542A9250D49EEB5416'
}

$requiredFreeGB = 50
$pp = Get-PackageParameters

# Package version 2024.a.b.c corresponds to Revit's registered version 24.a.b.c
$pkgVer = [version]$env:ChocolateyPackageVersion
$targetVersion = [version]::new($pkgVer.Major - 2000, $pkgVer.Minor, $pkgVer.Build, $pkgVer.Revision)

# ---------- 1. Pre-flight checks (fail early, change nothing) ----------
$os = Get-CimInstance Win32_OperatingSystem
if ([int]$os.BuildNumber -lt 17763) {
  throw "Revit 2024 requires 64-bit Windows 10 version 1809 (build 17763) or later, or Windows 11. This machine is on build $($os.BuildNumber)."
}
if (-not [Environment]::Is64BitOperatingSystem) {
  throw 'Revit 2024 requires 64-bit Windows.'
}

$existing = Get-Revit2024Entry
if ($existing -and (Get-Revit2024ExePath) -and (Get-EntryVersion $existing) -ge $targetVersion) {
  Write-Host "Revit 2024 $($existing.DisplayVersion) is already installed (package targets $targetVersion). Nothing to do."
  return
}
if ($existing -and -not (Get-Revit2024ExePath)) {
  Write-Warning 'Found a Revit 2024 registration but Revit.exe is missing (likely left over from an earlier uninstall). Reinstalling.'
}

if ((Test-RevitRunning) -and -not $pp['IgnoreRunning']) {
  throw 'Revit is currently running. This package never closes Revit, so nobody loses unsaved work. Close Revit and run the install again, or pass /IgnoreRunning.'
}

if ((Test-PendingReboot) -and -not $pp['IgnorePendingReboot']) {
  throw 'Windows reports a pending reboot, which commonly causes the Autodesk installer to fail. Restart the computer and run the install again, or pass /IgnorePendingReboot.'
}

$sysDrive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
$freeGB = [math]::Round($sysDrive.Free / 1GB, 1)
if ($freeGB -lt $requiredFreeGB) {
  throw "Revit 2024 needs about $requiredFreeGB GB free on $($env:SystemDrive) during installation. Only $freeGB GB is free."
}

# ---------- 2. Get the installer files ----------
$workDir = Join-Path $env:TEMP "revit2024\$($env:ChocolateyPackageVersion)"
$partsDir = Join-Path $workDir 'parts'
$extractDir = Join-Path $workDir 'extracted'
$setup = $null

try {
  New-Item -ItemType Directory -Path $partsDir, $extractDir -Force | Out-Null

  $src = $pp['SourcePath']
  if ($src -and (Test-Path -LiteralPath (Join-Path $src 'setup.exe'))) {
    Write-Host "Using extracted installer at $src"
    $setup = Join-Path $src 'setup.exe'
  }
  else {
    foreach ($name in $parts.Keys) {
      $dest = Join-Path $partsDir $name
      if ($src) {
        $local = Join-Path $src $name
        if (-not (Test-Path -LiteralPath $local)) {
          throw "SourcePath '$src' must contain setup.exe or all five Revit 2024 .sfx.exe parts. Missing: $name"
        }
        Write-Host "Using local part $local (verifying checksum)"
        Get-ChecksumValid -File $local -Checksum $parts[$name] -ChecksumType 'sha256'
        Copy-Item -LiteralPath $local -Destination $dest -Force
      }
      else {
        Get-ChocolateyWebFile -PackageName $env:ChocolateyPackageName `
          -FileFullPath $dest -Url64bit "$baseUrl/$name" `
          -Checksum64 $parts[$name] -ChecksumType64 'sha256'
      }
    }

    # The first part extracts all five. -suppresslaunch stops it from starting setup itself.
    $first = Join-Path $partsDir ($parts.Keys | Select-Object -First 1)
    Write-Host "Extracting Revit 2024 installer to $extractDir..."
    Start-ChocolateyProcessAsAdmin -ExeToRun $first `
      -Statements "-suppresslaunch -d `"$extractDir`"" -ValidExitCodes @(0) | Out-Null
    Remove-Item -LiteralPath $partsDir -Recurse -Force -ErrorAction SilentlyContinue

    $found = Get-ChildItem -Path $extractDir -Filter 'setup.exe' -Recurse -ErrorAction SilentlyContinue |
      Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if (-not $found) { throw 'setup.exe was not found in the extracted Revit 2024 files.' }
    $setup = $found.FullName
  }

  # ---------- 3. Install ----------
  Install-ChocolateyInstallPackage -PackageName 'Revit 2024' `
    -FileType 'exe' -File $setup -SilentArgs '-q' `
    -ValidExitCodes @(0, 3010, 1641)

  Write-Host 'Waiting for the Autodesk installer to finish. This can take several minutes...'
  Wait-AutodeskInstaller -TimeoutMinutes 120 -WorkDir $workDir

  # ---------- 4. Verify Revit 2024 actually installed ----------
  $deadline = (Get-Date).AddMinutes(10)
  do {
    $installed = if (Test-Revit2024Installed) { Get-Revit2024Entry } else { $null }
    if ($installed) { break }
    Start-Sleep -Seconds 20
  } while ((Get-Date) -lt $deadline)

  if (-not $installed) {
    throw 'The Autodesk installer finished but Revit 2024 is not installed. Check the Autodesk logs in %TEMP%\Autodesk and C:\ProgramData\Autodesk\ODIS.'
  }
  Write-Host "Revit 2024 $($installed.DisplayVersion) installed. Other Revit versions and add-ons were not touched."
  if (Test-PendingReboot) {
    Write-Warning 'A restart is required to finish the installation.'
  }

  # Tell anyone signed in to restart when convenient. A restart finishes any pending
  # setup and refreshes the Start menu, which may not list Revit 2024 until then.
  # This never restarts the computer itself.
  if (-not $pp['NoRestartPrompt']) {
    $msgExe = Join-Path $env:WINDIR 'System32\msg.exe'
    if (Test-Path $msgExe) {
      $text = 'Autodesk Revit 2024 has been installed. Please save your work and restart your computer when convenient so Revit 2024 appears in the Start menu and setup can finish.'
      try { & $msgExe '*' /TIME:43200 $text 2>$null } catch { }
    }
    Write-Host 'Signed-in users were asked to restart when convenient.'
  }
}
finally {
  # ---------- 5. Clean up ----------
  if (-not $pp['KeepFiles'] -and (Test-Path -LiteralPath $workDir)) {
    Write-Host "Removing temporary installer files from $workDir"
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    $parentDir = Split-Path -Parent $workDir
    if ((Test-Path -LiteralPath $parentDir) -and -not (Get-ChildItem -LiteralPath $parentDir -Force -ErrorAction SilentlyContinue)) {
      Remove-Item -LiteralPath $parentDir -Force -ErrorAction SilentlyContinue
    }
  }
}
