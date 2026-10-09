# Shared helpers for the revit2027 package.

# The Revit 2027 product itself. Anchored so add-ons and other Revit years never match.
$script:Revit2027NamePattern = '^(Autodesk )?Revit 2027$'

# Companion components installed by the Revit 2027 bundle, e.g.
# "Autodesk Revit Add-Ins Manager 2027", "Steel Connections Content for Revit 2027",
# "OpenStudio CLI For Revit 2027". Must mention Revit and end in 2027.
$script:Revit2027ComponentPattern = 'Revit.*\b2027$'

$script:UninstallKeyPaths = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

function Get-UninstallEntries {
  Get-ItemProperty -Path $script:UninstallKeyPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match $script:Revit2027NamePattern }
}

# Revit 2027 and the components its installer adds. Only entries published by Autodesk,
# plus the NREL OpenStudio CLI that the Revit installer bundles. Third-party add-ons that
# happen to target Revit 2027 are left alone.
function Get-Revit2027Components {
  Get-ItemProperty -Path $script:UninstallKeyPaths -ErrorAction SilentlyContinue |
    Where-Object {
      $_.DisplayName -and (
        ($_.DisplayName -match $script:Revit2027NamePattern) -or
        (($_.DisplayName -match $script:Revit2027ComponentPattern) -and
         (($_.Publisher -like 'Autodesk*') -or ($_.DisplayName -eq 'OpenStudio CLI For Revit 2027')))
      )
    }
}

function Get-EntryVersion($Entry) {
  try { [version]$Entry.DisplayVersion } catch { [version]'0.0' }
}

function Get-Revit2027Entry {
  Get-UninstallEntries |
    Sort-Object { Get-EntryVersion $_ } -Descending |
    Select-Object -First 1
}

function Get-Revit2027ExePath {
  $paths = @()
  foreach ($e in (Get-UninstallEntries)) {
    if ($e.InstallLocation) { $paths += (Join-Path $e.InstallLocation 'Revit.exe') }
  }
  $paths += (Join-Path $env:ProgramFiles 'Autodesk\Revit 2027\Revit.exe')
  $paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

# Installed means registered AND the program is actually on disk.
# A registry entry alone can be a leftover from a partial uninstall.
function Test-Revit2027Installed {
  [bool]((Get-Revit2027Entry) -and (Get-Revit2027ExePath))
}

function Test-PendingReboot {
  # Only the two keys that reliably indicate a required reboot.
  # PendingFileRenameOperations is skipped because it produces frequent false positives.
  $keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
  )
  foreach ($k in $keys) { if (Test-Path $k) { return $true } }
  return $false
}

function Test-RevitRunning {
  [bool](Get-Process -Name 'Revit' -ErrorAction SilentlyContinue)
}

function Test-OdisEntry($Entry) {
  [bool]($Entry.UninstallString -match 'Installer\.exe')
}

# Removes one uninstall entry using the method its own registration describes.
function Invoke-EntryUninstall($Entry) {
  $valid = @(0, 1605, 1614, 1641, 3010)
  $us = [string]$Entry.UninstallString
  $keyName = Split-Path $Entry.PSPath -Leaf

  if ($us -match '^\s*"?(?<exe>[^"]*Installer\.exe)"?\s*(?<args>.*)$') {
    # Autodesk ODIS registration: use Autodesk's own uninstaller, silently.
    $exe = $Matches['exe']
    $uArgs = $Matches['args']
    if ($uArgs -notmatch '(^|\s)-q(\s|$)') { $uArgs = "$uArgs -q" }
    Uninstall-ChocolateyPackage -PackageName $Entry.DisplayName -FileType 'exe' `
      -SilentArgs $uArgs -File $exe -ValidExitCodes $valid
    Wait-AutodeskInstaller -TimeoutMinutes 60 -GraceSeconds 30
    return
  }

  $guid = $null
  if ($keyName -match '^\{[0-9A-Fa-f-]{36}\}$') { $guid = $keyName }
  elseif ($us -match '(?<g>\{[0-9A-Fa-f-]{36}\})') { $guid = $Matches['g'] }

  if ($guid -and (($us -match 'msiexec') -or ($keyName -eq $guid))) {
    Uninstall-ChocolateyPackage -PackageName $Entry.DisplayName -FileType 'msi' `
      -SilentArgs "$guid /qn /norestart" -File '' -ValidExitCodes $valid
    return
  }

  Write-Warning "Unrecognized uninstall method for '$($Entry.DisplayName)'. Remove it from Settings > Apps."
}

# Autodesk's setup.exe hands off to a background installer (ODIS) and exits early.
# Wait for that installer to finish, with a timeout.
function Wait-AutodeskInstaller {
  param(
    [int]$TimeoutMinutes = 120,
    [int]$GraceSeconds = 60,
    [string]$WorkDir = ''
  )
  Start-Sleep -Seconds $GraceSeconds
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  while ($true) {
    $busy = Get-Process -Name 'Installer', 'setup' -ErrorAction SilentlyContinue |
      Where-Object {
        ($_.Path -like '*AdODIS*') -or
        ($WorkDir -and $_.Path -like "$WorkDir*")
      }
    if (-not $busy) { return }
    if ((Get-Date) -gt $deadline) {
      throw "The Autodesk installer was still running after $TimeoutMinutes minutes."
    }
    Write-Host 'Autodesk installer still running, checking again in 30 seconds...'
    Start-Sleep -Seconds 30
  }
}
