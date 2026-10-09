$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $toolsDir 'helpers.ps1')

# Removes Revit 2027 and the components its installer added.
# Other Revit years, shared Autodesk components, and third-party add-ons are never touched.

if (Test-RevitRunning) {
  throw 'Revit is currently running. Close Revit and run the uninstall again. This package never closes Revit.'
}

if (-not (Get-Revit2027Components)) {
  Write-Warning 'Revit 2027 is not registered as installed. Nothing to remove.'
  return
}

# 1. Autodesk's own uninstaller first. It removes the product bundle and usually most components.
foreach ($entry in @(Get-Revit2027Components | Where-Object { Test-OdisEntry $_ })) {
  Write-Host "Removing $($entry.DisplayName) with the Autodesk uninstaller..."
  Invoke-EntryUninstall $entry
}

# 2. Anything still registered: remove each by its own registered method.
foreach ($entry in @(Get-Revit2027Components)) {
  Write-Host "Removing remaining component: $($entry.DisplayName)"
  Invoke-EntryUninstall $entry
}

# 3. Report anything left over instead of failing silently.
$left = @(Get-Revit2027Components)
if ($left.Count -gt 0) {
  Write-Warning ("These Revit 2027 entries are still registered: " + (($left | ForEach-Object DisplayName) -join ', ') + '. Remove them from Settings > Apps.')
}
else {
  Write-Host 'Revit 2027 and its components removed. Other Revit versions and add-ons were not touched.'
}
