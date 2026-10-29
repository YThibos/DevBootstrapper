# Getting started

## 1. Prerequisites

- Windows 10 or 11.
- WSL2 with an Ubuntu distribution and its Linux user created.
  If either is missing, the installer stops and prints the exact command, for example `wsl --install -d Ubuntu-26.04` (run as administrator, then reboot and open Ubuntu once).
- Optional: Docker Desktop with *Settings > Resources > WSL integration* enabled for your Ubuntu distribution.

## 2. Install

In a normal PowerShell window (an elevated one while your WSL release refuses `wsl.exe` without administrator rights, as WSL 3.0.3 and 3.0.4 do):

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

`devup --first-run` walks through five numbered sections:

1. **Machine profile**: `home` on the desktop PC, `work` on the work laptop.
   It decides the default git context outside `sources/` and whether proxy questions are asked.
2. **Network**: proxy and corporate certificate (work profile), see [network.md](network.md).
   Sections 1 and 2 end with a summary of your answers; answer `n` to go through them again.
3. **Shell and WSL**: creates `.secrets`, sets `systemd=true` and `appendWindowsPath=false` in `/etc/wsl.conf` and adds two small blocks to `~/.bashrc`.
4. **Git identities**: your commit names and emails for `home` and `work`, and your forge accounts, each shown for review before it is saved, then a review menu to change anything. See [identities.md](identities.md).
5. **Install**: every tool, with a summary at the end.

A wrong answer is asked again instead of stopping the setup.
The first tool installation takes a while; later updates are quick.
Afterwards fill in your tokens with the `secrets` command and check them with `gitid doctor`.

## 4. Every day

Start "WezTerm (DevBootstrapper)" from the Start menu.
On the first start of the day an extra tab runs the update; type your `sudo` password there.
Run `dev` for an overview and `dev cheat` for the cheat sheet.

## Uninstall

1. `devup --unlink` removes every link and the `~/.bashrc` blocks.
2. Delete `~/development`.
3. On Windows, delete `C:\development\tools\wezterm`, `C:\development\tools\launcher` and the Start-menu shortcut, and restore `.wslconfig` from its `.devboot-backup-*` copy if you let the installer change it.

Files replaced by links during setup are kept in `~/development/tmp/backup-<date>/`.
