# Getting started

## 1. Prerequisites

- Windows 10 or 11.
- WSL2 with an Ubuntu distribution and its Linux user created.
  If either is missing, the installer stops and prints the exact command, for example `wsl --install -d Ubuntu-26.04` (run as administrator, then reboot and open Ubuntu once).
- Optional: Docker Desktop with *Settings > Resources > WSL integration* enabled for your Ubuntu distribution.

## 2. Install

In a normal PowerShell window:

```powershell
irm https://raw.githubusercontent.com/YThibos/DevBootstrapper/main/windows/install.ps1 | iex
```

To install from another branch, or pick the distribution explicitly:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YThibos/DevBootstrapper/main/windows/install.ps1))) -Branch main -Distro Ubuntu-26.04
```

The installer:

1. Checks WSL2 and Ubuntu.
2. Offers to tune `%USERPROFILE%\.wslconfig` (mirrored networking, DNS tunnelling, the Windows proxy inside WSL, a memory cap). This is optional.
3. Downloads WezTerm nightly into `C:\development\tools\wezterm` and verifies its checksum.
4. Installs the launcher into `C:\development\tools\launcher` and a Start-menu shortcut "WezTerm (DevBootstrapper)".
5. Clones this repository into `~/development` in WSL and runs `devup --first-run`.

## 3. First run

`devup --first-run` asks a few questions once:

- **Machine profile**: `home` on the desktop PC, `work` on the work laptop.
  It decides the default git context outside `sources/` and whether proxy questions are asked.
- **Proxy and corporate certificate** (work profile): see [network.md](network.md).
- **Git contexts and accounts**: your commit names and emails for `home` and `work`, and your forge accounts. See [identities.md](identities.md).

It then creates `.secrets` (fill in your tokens with the `secrets` command), sets `systemd=true` and `appendWindowsPath=false` in `/etc/wsl.conf`, adds two small blocks to `~/.bashrc`, and installs every tool.
The first tool installation takes a while; later updates are quick.

## 4. Every day

Start "WezTerm (DevBootstrapper)" from the Start menu.
On the first start of the day an extra tab runs the update; type your `sudo` password there.
Run `dev` for an overview and `dev cheat` for the cheat sheet.

## Uninstall

1. `devup --unlink` removes every link and the `~/.bashrc` blocks.
2. Delete `~/development`.
3. On Windows, delete `C:\development\tools\wezterm`, `C:\development\tools\launcher` and the Start-menu shortcut, and restore `.wslconfig` from its `.devboot-backup-*` copy if you let the installer change it.

Files replaced by links during setup are kept in `~/development/tmp/backup-<date>/`.
