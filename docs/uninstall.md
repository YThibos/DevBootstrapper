# Uninstall

Two ways out:

- **[Full reset](#full-reset)**: removes DevBootstrapper, EDI and the whole Ubuntu distribution, so the next install starts from nothing, as on a new machine.
  Use it to test the install again.
- **[Keep Ubuntu](#remove-devbootstrapper-but-keep-ubuntu)**: removes DevBootstrapper and EDI but keeps the distribution and everything else in it.

Run the PowerShell commands in an elevated PowerShell window while your WSL release refuses `wsl.exe` without administrator rights, as WSL 3.0.3 and 3.0.4 do.

## Full reset

### 1. Save what you want to keep

Removing the distribution in step 3 deletes everything inside it, without asking again.
Look for, inside WSL:

- Work that is not pushed, in `~/development/sources/` and in the EDI checkout.
  This lists every repository with local changes or commits that are on no remote:

  ```bash
  for d in ~/development/sources/*/*/ ~/EDI/; do
    [ -d "$d/.git" ] || continue
    s=$(git -C "$d" status --porcelain); u=$(git -C "$d" log --oneline --branches --not --remotes)
    [ -z "$s$u" ] || printf '== %s\n%s\n%s\n' "$d" "$s" "$u"
  done
  ```

- The EDI home `~/.edi`: EDI's memory, backlog, decisions and `config/personal.yaml`.
  To keep a copy on Windows: `cp -r ~/.edi /mnt/c/development/backup/edi-home-$(date +%F)`.
- Your tokens in `~/development/.secrets`, unless they are in your password manager anyway.
- SSH keys in `~/.ssh`, if `gitid` generated any.

Everything else comes back with the next install: `.local/profile.env`, the git identities and `.local/wezterm.lua` are asked for or created again.

### 2. Close everything that uses the distribution

Close every WezTerm window, quit Docker Desktop and close IDEs with projects in WSL, then:

```powershell
wsl --shutdown
```

### 3. Remove the Ubuntu distribution

```powershell
wsl --list --verbose
wsl --unregister Ubuntu
```

Use the name `wsl --list` shows, such as `Ubuntu-26.04`.
This deletes the dev home `~/development` with every tool, cache and setting, EDI (`~/.edi`, `~/.local/bin/edi*` and the checkout), `/etc/wsl.conf`, the apt packages and the `~/.bashrc`, `~/.zshenv` and `~/.zshrc` blocks.
`devup --unlink` is not needed first.

### 4. Remove the Windows side

```powershell
Get-Process wezterm-gui, wezterm-mux-server -ErrorAction SilentlyContinue | Stop-Process
$tools = 'C:\development\tools'
foreach ($dir in 'wezterm', 'wezterm.previous', 'wezterm.staging', 'wezterm.swap', 'launcher') {
    Remove-Item -Recurse -Force (Join-Path $tools $dir) -ErrorAction SilentlyContinue
}
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\WezTerm (DevBootstrapper).lnk" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:USERPROFILE\.local\share\wezterm" -ErrorAction SilentlyContinue
```

- `wezterm` and `wezterm.previous` are the WezTerm builds the launcher installed; the other two only exist after an interrupted update or rollback.
- `launcher` holds the launcher, the WezTerm stub, the machine values `install.ps1` wrote (`devboot-local.lua`), the update state (`state.json`) and `launcher.log`.
  Left behind, a new install would find today's update already done.
- `.local\share\wezterm` holds WezTerm's logs and sockets.

### 5. Restore `.wslconfig`

Only if you answered yes to the installer's `.wslconfig` question.
Each such run saved the file it changed as `.wslconfig.devboot-backup-<date>-<time>`, so the oldest backup is your file from before the first install.
This puts it back and removes the backups:

```powershell
$backups = @(Get-ChildItem "$env:USERPROFILE\.wslconfig.devboot-backup-*" | Sort-Object Name)
if ($backups.Count -gt 0) {
    Copy-Item $backups[0].FullName "$env:USERPROFILE\.wslconfig" -Force
    $backups | Remove-Item
}
```

Without any backup, the first install created `.wslconfig`: delete it if you had none before.
The restored file applies from the next WSL start.
To keep the installer away from it next time, answer no, or start the installer with `-WslConfig no`.

### 6. Check that nothing is left

```powershell
wsl --list --verbose
Test-Path 'C:\development\tools\wezterm', 'C:\development\tools\launcher', "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\WezTerm (DevBootstrapper).lnk"
Get-ChildItem $env:USERPROFILE -Force -Filter '.wslconfig*'
```

The distribution is gone from the list, every `Test-Path` says `False`, and only `.wslconfig` itself remains, if you have one.

### What stays

These were never DevBootstrapper's, so the reset leaves them alone:

- Everything else in `C:\development`, such as `sources`, `backup` and other tools in `tools`.
- Docker Desktop and its own `docker-desktop` distribution.
  Its WSL integration remembers Ubuntu by name; check *Settings > Resources > WSL integration* after the next install.
- A `%USERPROFILE%\.wezterm.lua` of your own: DevBootstrapper's WezTerm reads the stub next to `wezterm.exe` first and never reads this file.
- Windows Terminal's Ubuntu profile, which WSL manages and hides once the distribution is gone.

### 7. Install fresh

Install Ubuntu again and open it once to create your Linux user, then follow [getting-started.md](getting-started.md):

```powershell
wsl --install -d Ubuntu
```

## Remove DevBootstrapper but keep Ubuntu

1. Inside WSL, move what you keep out of `~/development` first: your clones in `sources/`, and the originals of files `devup` replaced by links, in `tmp/backup-<date>/`.
2. Remove the links and the shell blocks, then the dev home:

   ```bash
   devup --unlink
   rm -rf ~/development
   ```

3. Remove EDI, if it is installed:

   ```bash
   rm -f ~/.local/bin/edi ~/.local/bin/edi-core ~/.local/bin/helloedi
   rm -rf ~/.edi
   ```

   Then delete the EDI checkout.
4. `devup` set `systemd=true` and `appendWindowsPath=false` in `/etc/wsl.conf` and installed the apt packages in `install/apt-packages.txt`.
   Both stay; edit `/etc/wsl.conf` with `sudoedit` to change it back, then run `wsl --terminate <distro>` from Windows.
5. On Windows, follow steps 4 to 6 of the full reset.
