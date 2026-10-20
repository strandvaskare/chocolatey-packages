# revit2024 Chocolatey package

Installs Autodesk Revit 2024 side by side with other Revit versions. Built as a safer alternative to the community `revit` package, whose install script uninstalls every program matching `*Revit*` (other Revit years and all Revit add-ons) and deletes matching folders under `C:\Program Files\Autodesk`.

## Files

```
revit2024/
  revit2024.nuspec              package metadata and description
  tools/
    chocolateyinstall.ps1       install logic
    chocolateyuninstall.ps1     removes Revit 2024 only
    helpers.ps1                 shared functions (product match, reboot check, installer wait)
    .skipAutoUninstall          stops Chocolatey's auto-uninstaller from guessing with a wildcard
```

## Before you publish

1. In `revit2024.nuspec`, replace `REPLACE-WITH-YOUR-CHOCOLATEY-USERNAME` and the `packageSourceUrl` repo path. Community moderation requires a public source repo, so put this folder on GitHub first.
2. Confirm the Autodesk download URL and SHA-256 in `chocolateyinstall.ps1` still match the current Revit 2024 release. They were taken from the existing community package (2024.0.4). When Autodesk ships a new 2024 update, bump the nuspec version, URL and checksum together.

## Build and test locally (on a Windows 10 or 11 test machine with Chocolatey)

From an elevated PowerShell in the `revit2024` folder:

```powershell
choco pack
choco install revit2024 --source . -y --verbose
```

Check afterward:

- Revit 2024 appears in Settings > Apps.
- **Revit 2026 and every Revit 2026 add-on are still installed.**
- `C:\Windows\Temp\revit2024` (or your user `%TEMP%\revit2024`) is gone.
- Running the install a second time says it is already installed and does nothing.
- With Revit open, the install refuses to run.

Then test removal on the same machine:

```powershell
choco uninstall revit2024 -y --verbose
```

Revit 2024 should be gone and Revit 2026 untouched. The uninstall logic reads Autodesk's registered uninstall command and adds the silent flag. It is the part most worth watching on the first run.

## Publish to the Chocolatey community repository

```powershell
choco apikey --key <your-api-key> --source https://push.chocolatey.org/
choco push revit2024.2024.0.4.427.nupkg --source https://push.chocolatey.org/
```

Expect a manual moderation step. Like the existing `revit` package, the automated verifier will likely time out on the 9.6 GB download, so request a verifier exemption in the moderation comments and point the moderator to the side-by-side behavior as the reason this package exists.

## Tested

Verified on Windows 11 26H2 (workstation with Revit 2024.3 and Revit 2026 installed):

- All five Autodesk download parts are live and match the package's SHA-256 checksums.
- The first part extracts the full set with `-suppresslaunch -d <folder>` and waits until done. `Setup.exe` lands in a `Revit_2024_G1_Win_64bit_dlm` subfolder, which the package finds.
- Autodesk's manifest for this download reports version 24.0.4.427, matching the package version.
- With a newer Revit 2024 already installed (24.3.40.26), the package correctly reports it as installed and changes nothing.
- Works on Chocolatey 1.1.0 (the version JumpCloud pins) as well as 2.x.

The install and uninstall steps use the same Autodesk `Setup.exe -q` and ODIS uninstall logic as revit2027, which was tested end to end on Windows 11 26H2.

Tip: if you run this in a console window, don't click inside it while it works. Windows QuickEdit mode pauses the script until you press Esc or Enter.

## Package parameters

| Parameter | Effect |
|---|---|
| `/SourcePath:<path>` | Install from a folder containing all five official `.sfx.exe` parts (each checksum verified) or the extracted `setup.exe`, for example a NAS share |
| `/IgnoreRunning` | Install even if Revit is open. Revit is still never closed |
| `/IgnorePendingReboot` | Install even if Windows reports a pending reboot |
| `/KeepFiles` | Keep the downloaded and extracted files |
| `/NoRestartPrompt` | Skip the message asking signed-in users to restart. The package never restarts the machine either way |

Example:

```powershell
choco install revit2024 -y --params "'/SourcePath:\\nas\deploy\Revit2024'"
```

## Using it from JumpCloud

Add a Chocolatey app in Software Management with package ID `revit2024` and bind it to the target device group. Once it is approved on the community repository no custom repository URL is needed. Leaving "keep up to date" on is safe with this package, because new versions only ever install 2024.x.
