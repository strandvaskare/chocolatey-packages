# revit2027 Chocolatey package

Installs Autodesk Revit 2027 side by side with other Revit versions. Built as a safer alternative to the community `revit` package, whose install script uninstalls every program matching `*Revit*` (other Revit years and all Revit add-ons) and deletes matching folders under `C:\Program Files\Autodesk`.

## Files

```
revit2027/
  revit2027.nuspec              package metadata and description
  tools/
    chocolateyinstall.ps1       install logic
    chocolateyuninstall.ps1     removes Revit 2027 only
    helpers.ps1                 shared functions (product match, reboot check, installer wait)
    .skipAutoUninstall          stops Chocolatey's auto-uninstaller from guessing with a wildcard
```

## Before you publish

1. In `revit2027.nuspec`, replace `REPLACE-WITH-YOUR-CHOCOLATEY-USERNAME` and the `packageSourceUrl` repo path. Community moderation requires a public source repo, so put this folder on GitHub first.
2. Confirm the Autodesk download URL and SHA-256 in `chocolateyinstall.ps1` still match the current Revit 2027 release. They were taken from the existing community package (2027.0.4). When Autodesk ships a new 2027 update, bump the nuspec version, URL and checksum together.

## Build and test locally (on a Windows 11 test machine with Chocolatey)

From an elevated PowerShell in the `revit2027` folder:

```powershell
choco pack
choco install revit2027 --source . -y --verbose
```

Check afterward:

- Revit 2027 appears in Settings > Apps.
- **Revit 2026 and every Revit 2026 add-on are still installed.**
- `C:\Windows\Temp\revit2027` (or your user `%TEMP%\revit2027`) is gone.
- Running the install a second time says it is already installed and does nothing.
- With Revit open, the install refuses to run.

Then test removal on the same machine:

```powershell
choco uninstall revit2027 -y --verbose
```

Revit 2027 should be gone and Revit 2026 untouched. The uninstall logic reads Autodesk's registered uninstall command and adds the silent flag. It is the part most worth watching on the first run.

## Publish to the Chocolatey community repository

```powershell
choco apikey --key <your-api-key> --source https://push.chocolatey.org/
choco push revit2027.2027.0.4.412.nupkg --source https://push.chocolatey.org/
```

Expect a manual moderation step. Like the existing `revit` package, the automated verifier will likely time out on the 10 GB download, so request a verifier exemption in the moderation comments and point the moderator to the side-by-side behavior as the reason this package exists.

## Tested

Verified on Windows 11 26H2 with Revit 2026 installed:

- Install: downloads from Autodesk, verifies SHA-256, installs, confirms Revit.exe, cleans up temp files, prompts signed-in users to restart. Revit 2026 and all 2026 add-ons untouched.
- Start menu: Revit 2027 appears in Start search after the restart.
- Reinstall over a leftover registration: detected and reinstalled correctly.
- Uninstall: Autodesk uninstaller runs silently, all 2027 entries removed, all 2026 entries and shared components (Autodesk Genuine Service) kept.

Tip: if you run this in a console window, don't click inside it while it works. Windows QuickEdit mode pauses the script until you press Esc or Enter.

## Package parameters

| Parameter | Effect |
|---|---|
| `/SourcePath:<path>` | Install from the official `.7z` (checksum verified) or a folder containing extracted `setup.exe`, for example a NAS share |
| `/IgnoreRunning` | Install even if Revit is open. Revit is still never closed |
| `/IgnorePendingReboot` | Install even if Windows reports a pending reboot |
| `/KeepFiles` | Keep the downloaded and extracted files |
| `/NoRestartPrompt` | Skip the message asking signed-in users to restart. The package never restarts the machine either way |

Example:

```powershell
choco install revit2027 -y --params "'/SourcePath:\\nas\deploy\Revit2027'"
```

## Using it from JumpCloud

Add a Chocolatey app in Software Management with package ID `revit2027` and bind it to the target device group. Once it is approved on the community repository no custom repository URL is needed. Leaving "keep up to date" on is safe with this package, because new versions only ever install 2027.x.
