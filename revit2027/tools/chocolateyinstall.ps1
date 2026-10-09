$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $toolsDir 'helpers.ps1')

# Official Autodesk download for Revit 2027.0.4 (verified against the checksum below).
$url      = 'https://efulfillment.autodesk.com/NetSWDLD/ODIS/prd/2027/RVT/8CA3AC7D-FAD3-34CE-B228-4EE1B50E2D3E/SFX/RVT_2027_NA_win_db_002_002.7z'
$checksum = '68340AD12FE25D4077C50C2EBA42ECB42120DB6E6044A91903F36B7B36CD5122'

$requiredFreeGB = 45
$pp = Get-PackageParameters

# Package version 2027.a.b.c corresponds to Revit's registered version 27.a.b.c
$pkgVer = [version]$env:ChocolateyPackageVersion
$targetVersion = [version]::new($pkgVer.Major - 2000, $pkgVer.Minor, $pkgVer.Build, $pkgVer.Revision)

# ---------- 1. Pre-flight checks (fail early, change nothing) ----------
$os = Get-CimInstance Win32_OperatingSystem
if ([int]$os.BuildNumber -lt 22000) {
  throw "Revit 2027 requires Windows 11 (build 22000 or later). This machine is on build $($os.BuildNumber)."
}
if (-not [Environment]::Is64BitOperatingSystem) {
  throw 'Revit 2027 requires 64-bit Windows.'
}

$existing = Get-Revit2027Entry
if ($existing -and (Get-Revit2027ExePath) -and (Get-EntryVersion $existing) -ge $targetVersion) {
  Write-Host "Revit 2027 $($existing.DisplayVersion) is already installed (package targets $targetVersion). Nothing to do."
  return
}
if ($existing -and -not (Get-Revit2027ExePath)) {
  Write-Warning 'Found a Revit 2027 registration but Revit.exe is missing (likely left over from an earlier uninstall). Reinstalling.'
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
  throw "Revit 2027 needs about $requiredFreeGB GB free on $($env:SystemDrive) during installation. Only $freeGB GB is free."
}

# ---------- 2. Get the installer files ----------
$workDir = Join-Path $env:TEMP "revit2027\$($env:ChocolateyPackageVersion)"
$setup = $null

try {
  New-Item -ItemType Directory -Path $workDir -Force | Out-Null

  if ($pp['SourcePath']) {
    $src = $pp['SourcePath']
    if (Test-Path -LiteralPath (Join-Path $src 'setup.exe')) {
      Write-Host "Using extracted installer at $src"
      $setup = Join-Path $src 'setup.exe'
    }
    elseif ((Test-Path -LiteralPath $src -PathType Leaf) -and $src -like '*.7z') {
      Write-Host "Using local archive $src (verifying checksum)"
      Get-ChecksumValid -File $src -Checksum $checksum -ChecksumType 'sha256'
      Get-ChocolateyUnzip -FileFullPath $src -Destination (Join-Path $workDir 'extracted')
    }
    else {
      throw "SourcePath '$src' must be the official .7z archive or a folder containing setup.exe."
    }
  }
  else {
    $archive = Join-Path $workDir 'RVT_2027.7z'
    Get-ChocolateyWebFile -PackageName $env:ChocolateyPackageName `
      -FileFullPath $archive -Url64bit $url `
      -Checksum64 $checksum -ChecksumType64 'sha256'
    Get-ChocolateyUnzip -FileFullPath $archive -Destination (Join-Path $workDir 'extracted')
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
  }

  if (-not $setup) {
    $found = Get-ChildItem -Path (Join-Path $workDir 'extracted') -Filter 'setup.exe' -Recurse -ErrorAction SilentlyContinue |
      Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if (-not $found) { throw 'setup.exe was not found in the extracted Revit 2027 archive.' }
    $setup = $found.FullName
  }

  # ---------- 3. Install ----------
  Install-ChocolateyInstallPackage -PackageName 'Revit 2027' `
    -FileType 'exe' -File $setup -SilentArgs '-q' `
    -ValidExitCodes @(0, 3010, 1641)

  Write-Host 'Waiting for the Autodesk installer to finish. This can take several minutes...'
  Wait-AutodeskInstaller -TimeoutMinutes 120 -WorkDir $workDir

  # ---------- 4. Verify Revit 2027 actually registered ----------
  $deadline = (Get-Date).AddMinutes(10)
  do {
    $installed = if (Test-Revit2027Installed) { Get-Revit2027Entry } else { $null }
    if ($installed) { break }
    Start-Sleep -Seconds 20
  } while ((Get-Date) -lt $deadline)

  if (-not $installed) {
    throw 'The Autodesk installer finished but Revit 2027 is not registered as installed. Check the Autodesk logs in %TEMP%\Autodesk and C:\ProgramData\Autodesk\ODIS.'
  }
  Write-Host "Revit 2027 $($installed.DisplayVersion) installed. Other Revit versions and add-ons were not touched."
  if (Test-PendingReboot) {
    Write-Warning 'A restart is required to finish the installation.'
  }

  # Tell anyone signed in to restart when convenient. A restart finishes any pending
  # setup and refreshes the Start menu, which may not list Revit 2027 until then.
  # This never restarts the computer itself.
  if (-not $pp['NoRestartPrompt']) {
    $msgExe = Join-Path $env:WINDIR 'System32\msg.exe'
    if (Test-Path $msgExe) {
      $text = 'Autodesk Revit 2027 has been installed. Please save your work and restart your computer when convenient so Revit 2027 appears in the Start menu and setup can finish.'
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
