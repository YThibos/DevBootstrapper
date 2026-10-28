# Updates

## devup

`devup` installs and updates everything; the first install and a daily update run the same steps:

| Step | What it does |
|---|---|
| pull | Fast-forwards `~/development`. With local changes it skips and says so; commit or discard them first. |
| windows | Copies the launcher and WezTerm stub to `C:\development\tools\launcher` (WSL only). |
| certs | Adds the corporate root certificate to Ubuntu's trust store (work profile). |
| apt | apt proxy, git-core PPA, base packages, `apt-get upgrade` (asks for `sudo`). |
| render | Renders Maven and npm settings from templates into `.local/`. |
| links | Links tool configs into place and keeps the `~/.bashrc` blocks. |
| mise | Installs or updates mise and every tool, then removes versions no longer used. |
| certs-java | Imports the corporate certificate into every installed JDK. |
| identities | Regenerates the git identity config. |
| completions | Generates bash completions for installed tools. |
| doctor | Health report (also `dev doctor`). |

`devup --skip apt,mise` and `devup --only links` run part of it.
`devup --unlink` removes every link and the `~/.bashrc` blocks.

## Daily update

The first WezTerm start of each day opens an extra tab running `devup --daily`, where you type the `sudo` password.
Other terminals print a one-line reminder until the day's update has run.
`Ctrl+Shift+u` in WezTerm runs `devup` in a new tab at any time.

## WezTerm

The Start-menu shortcut runs `C:\development\tools\launcher\launcher.ps1`.
At most once a day it checks the nightly build; when a newer one exists and no WezTerm is running, it downloads it, verifies the published SHA-256, swaps it in and keeps the previous build.
Its log is `C:\development\tools\launcher\launcher.log`.

To go back to the previous build, close WezTerm and run in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File C:\development\tools\launcher\launcher.ps1 -Rollback
```
