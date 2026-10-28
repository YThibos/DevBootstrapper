# DevBootstrapper specification

Status: approved; v1 is implemented in this repository.
This is the canonical copy of the specification; the First Officer repository keeps a copy for the work-laptop investigation in section 18.
Section 21 records what is verified and what is not.

## 1. Goal

DevBootstrapper is a portable, self-updating developer toolkit: one repository that turns a Windows machine with WSL2 into the same development environment at home and at work.
It covers a Java developer who also does Angular front-end work, and it hosts agent tooling such as Claude Code and EDI (the successor of First Officer).
Prerequisites stay minimal, and after the one-time install everything happens inside WezTerm.

## 2. Scope

In scope for v1:

- Windows 10 or 11 as the host, with WSL2 running the latest stable Ubuntu release.
- WezTerm nightly, from the portable zip, as the terminal.
- A structured, modular bash setup under `~/development/bash/`.
- Installing and updating every listed tool, plus WezTerm itself.
- Home and work profiles, including a corporate proxy.
- Default Claude Code user settings.

Out of scope for v1:

- macOS, and Linux distributions other than Debian and Ubuntu.
- The Windows-native side (Git Bash for Windows, PowerShell, Command Prompt), planned as a later phase under `C:\development\` (section 15).
- Kubernetes tooling.
- Installing IDEs or Docker Desktop.
- Cloning First Officer or EDI.
- Automatic cleanup of `tmp/`.

## 3. Prerequisites

- Windows 10 or 11 on which the user may run PowerShell scripts.
- WSL2 with an Ubuntu distribution installed and its Linux user created.
- Docker Desktop with WSL integration enabled for that distribution (optional, but needed for the `docker` command).
- Network access to GitHub and the tool download hosts, either directly or through the Windows proxy configuration.

The installer detects a missing WSL or Ubuntu and prints the exact command to install the newest Ubuntu release that `wsl --list --online` offers.
It does not install WSL or Ubuntu itself, because that needs administrator rights and a reboot.

## 4. Architecture

Three layers, each with a single entry point.

| Layer | Location | Entry point | Runs |
|---|---|---|---|
| Windows host | `C:\development\tools\` | `windows/install.ps1`, then the WezTerm launcher | Install once; the launcher runs every time WezTerm starts |
| WezTerm config | `~/development/config/wezterm/` | A stub `wezterm.lua` next to `wezterm.exe` that loads the repository config | Every WezTerm start, with hot reload |
| WSL shell | `~/development/` | `bash/bootstrap.sh`, sourced from `~/.bashrc` | Every shell |

Two jobs are kept strictly apart:

- Shell setup (`bash/bootstrap.sh`) is sourced by every shell.
  It must be fast, never touches the network and never asks for `sudo`.
- Install and update (`devup`) is idempotent and runs explicitly or once per day.
  A first install and a daily update are the same code path.

## 5. Dev home layout

The dev home is `~/development` on the WSL ext4 filesystem, never under `/mnt/c`, because cross-filesystem I/O is slow.
The DevBootstrapper repository is cloned directly as the dev home.
On Windows, `C:\development\` is the Windows-side dev home.
In v1 the toolkit uses only `C:\development\tools\wezterm\` and `C:\development\tools\launcher\` there; the rest is reserved for the later Windows-native phase.

```
~/development/
├── bash/
│   ├── bootstrap.sh        # sole entry point: "bootstrap.sh env" (environment) or "bootstrap.sh" (interactive)
│   ├── env.sh              # environment layer: DEV_HOME, PATH, caches, mise, proxy, certificate
│   ├── aliases.sh
│   ├── functions.sh
│   ├── completions.sh
│   ├── prompt.sh
│   ├── tools/              # one small file per tool: history, mise, git, java, node, docker, fzf, zoxide, wsl
│   └── local.sh            # gitignored, per-machine shell overrides
├── bin/                    # dev, devup, gitid, use-version, mvnuse, jdkuse, git helpers
│   └── wrappers/           # gh and glab wrappers that pick the account (section 10.1)
├── lib/                    # shared shell libraries: common, identity, links, render
├── install/
│   ├── devup.sh            # install and update, idempotent
│   ├── doctor.sh           # health report
│   └── apt-packages.txt
├── config/
│   ├── mise/config.toml    # the shared tool manifest
│   ├── wezterm/wezterm.lua
│   ├── git/                # gitconfig and global ignore
│   ├── maven/settings.xml  # template, rendered into .local/ (section 10)
│   ├── npm/npmrc           # template, rendered into .local/
│   ├── tmux/tmux.conf
│   ├── starship.toml
│   └── claude/             # settings.json and CLAUDE.md (section 14)
├── docs/                   # user documentation, read with dev docs
├── tests/                  # sandboxed tests, run by tests/run.sh and CI
├── windows/
│   ├── install.ps1         # one-time Windows installer
│   ├── launcher.ps1        # WezTerm updater and launcher
│   └── wezterm-stub.lua    # copied next to wezterm.exe
├── sources/
│   ├── home/               # "home" context: personal commit identity and accounts
│   ├── work/               # "work" context: work commit identity and accounts
│   └── <context>/          # any further context added with gitid (section 10.1)
├── tools/                  # every mise-managed tool, tools/cache/ for all caches, tools/state/ for stamps
├── tmp/                    # empty scratch directory, no automatic cleanup
├── .local/                 # gitignored machine settings: profile, git identities, version defaults, rendered configs
├── .local.example/         # tracked template for .local/profile.env
├── .secrets                # gitignored credentials, chmod 600
├── .secrets.example        # tracked list of expected keys, no values
├── .github/workflows/ci.yml
├── README.md
└── SPEC.md                 # this spec
```

## 6. Version control model

- `.gitignore` is an allow-list: it starts with `/*` and re-includes only `bash/`, `install/`, `config/`, `windows/`, the dotfile templates and the top-level docs.
  `sources/`, `tools/`, `tmp/`, `.local/` and `.secrets` therefore cannot be committed by accident, even if a rule is forgotten.
- `tmp/` exists through a tracked `tmp/.gitkeep`, and its contents are ignored.
- `sources/home/` and `sources/work/` exist through tracked `.gitkeep` files, and the checkouts inside them are ignored.
- `.gitattributes` forces LF line endings for `*.sh`, `*.lua`, `*.toml` and configuration files, and CRLF for `*.ps1` and `*.cmd`.
- No tracked file may contain an employer name, internal host, proxy address, personal email address or credential.
  The repository is treated as public, so everything machine- or employer-specific lives in `.local/` or `.secrets`.

## 7. Install flow

### 7.1 Windows installer

The user runs one PowerShell line that downloads and runs `windows/install.ps1` from the repository's default branch.
The installer:

1. Detects WSL2 and the installed Ubuntu distribution, and asks which distribution to use if there are several.
   If WSL or Ubuntu is missing, it prints the install command for the newest Ubuntu release and stops.
2. Optionally writes or merges `%USERPROFILE%\.wslconfig` (opt-in prompt): mirrored networking, `autoProxy`, `dnsTunneling` and a memory cap.
3. Downloads the WezTerm nightly portable zip, verifies its checksum when one is published, and extracts it into `C:\development\tools\wezterm\`.
4. Copies `wezterm-stub.lua` next to `wezterm.exe` as `wezterm.lua`, and writes a small local file with the distribution name and Linux home path.
5. Copies `launcher.ps1` into `C:\development\tools\launcher\` and creates a Start-menu shortcut that runs it with a hidden window.
6. Runs the WSL first install: `git clone` of the repository into `~/development`, then `install/devup.sh --first-run`.
7. Restarts WSL if `/etc/wsl.conf` changed, then starts WezTerm through the launcher.

### 7.2 WSL first run

`devup --first-run` is interactive once:

1. Asks for the machine profile (`home` on the desktop PC, `work` on the work laptop) and writes `.local/profile.env`.
2. Runs `gitid` setup for the `home` and `work` contexts and at least one account, and sets this machine's default context from the profile.
   More accounts and contexts can be added later at any time (section 10.1).
3. Detects the proxy from the environment WSL inherited from Windows, asks to confirm or enter it, and records it in `.local/profile.env`.
4. Creates `.secrets` from `.secrets.example` with mode 600.
5. Writes `/etc/wsl.conf` (`systemd=true`, `appendWindowsPath=false`) with `sudo`.
6. Adds the two bootstrap blocks to `~/.bashrc` (section 8), then runs the normal update path (section 11).

## 8. Shell layer

`~/.bashrc` gains two small marked blocks, both calling `bash/bootstrap.sh`:

1. At the very top, `bootstrap.sh env` loads the environment layer (`env.sh`, `.local/profile.env` and `.secrets`) before Ubuntu's "return if not interactive" guard, so login shells such as `bash -lc` get it too.
   It sets `DEV_HOME`, PATH (wrappers, DevBootstrapper commands, tool binaries, mise shims), `XDG_CACHE_HOME=$DEV_HOME/tools/cache`, the `MISE_*` directories, the proxy and certificate variables and `BROWSER=wslview`.
2. At the bottom, `bootstrap.sh` loads the interactive layer after Ubuntu's own defaults, so DevBootstrapper's history settings, aliases and prompt win.
   It sources an explicit, ordered list: `tools/*.sh` (including full `mise activate bash`), `aliases.sh`, `functions.sh`, `completions.sh` and `prompt.sh`, then `local.sh` last.

A single line could not do both: placed at the top, Ubuntu's later defaults override the interactive settings, and placed at the bottom, non-interactive shells never reach it.

Requirements:

- Interactive startup stays under 200 ms, measured with `time bash -i -c exit`.
- No network access, no `sudo` and no prompts.
- Programs started without an interactive shell must see the same tools and the same git identity: EDI and Claude Code workers in tmux, git hooks, and IDE integrations.
  For that reason, configurations that other programs read live at the tools' default locations as symlinks into the repository (section 10).
  Environment variables are used only where nothing else reads the setting.
- A missing optional tool never breaks shell startup.
  Each `tools/*.sh` file checks for its tool and skips silently when it is absent.
- When the last successful update is older than one day, an interactive shell prints a one-line reminder to run `devup`.
  This covers terminals other than WezTerm.

### 8.1 Help, cheat sheet and documentation

The `dev` command is the toolkit's front door:

- `dev` prints an overview of the toolkit and its commands.
- `dev cheat [filter]` prints a cheat sheet of commands, aliases, functions, WezTerm keys and tmux keys.
  Entries come from `#: usage | description` lines (`--:` in Lua) placed next to what they describe, so the sheet never drifts from the code.
- `dev docs [topic]` lists the documentation topics in `docs/`, or renders one in the terminal (glow, else bat, else less); `dev docs spec` shows this spec.
- `dev ids` prints the git account and context table (`gitid list`).
- `dev doctor` prints the health report, and `dev startup-time` measures interactive shell startup.

## 9. Tool catalogue

Source rule: use mise when it offers a prebuilt binary; otherwise use apt; otherwise use the tool's own default platform.
A mise entry that only compiles from source through an asdf plugin counts as "not available in mise".
That is why git comes from apt; tmux has a prebuilt mise build and therefore comes from mise.

| Tool | Source | Version policy |
|---|---|---|
| Java JDK (8, 11, 17, 21, 25) | mise, Eclipse Temurin (OpenJDK builds) | Every LTS that is still supported, latest patch; default 25 |
| Maven 3 and Maven 4 | mise | Both installed; default is the 3.10 line (currently 3.10.0) until the captain says otherwise; switch with `mvnuse` (section 9.1) |
| Maven daemon (mvnd) | mise | Latest |
| Gradle | mise | Latest |
| Node.js and npm | mise | Current LTS; npm ships with Node |
| Angular CLI | mise, `npm:@angular/cli` | Latest, as a convenience; projects use their own local version through `npx` |
| Python | mise | Latest stable |
| uv | mise | Latest |
| Claude Code | mise (registry entry if present, else `npm:@anthropic-ai/claude-code`) | Latest |
| gh, glab, jq, yq, ripgrep, fd, fzf, bat, eza, zoxide, delta, lazygit, lazydocker, starship, xh, glow, shellcheck, shfmt, tmux | mise | Latest |
| git | apt, from the `git-core` PPA when it publishes for the installed Ubuntu release, otherwise the distribution package | Latest stable |
| Base packages (build-essential, ca-certificates, curl, wget, zip, unzip, gnupg, bash-completion, less, file, openssh-client, wslu) | apt | Distribution version |
| docker CLI and compose | Docker Desktop WSL integration | Managed by Docker Desktop; `doctor` only checks it |
| WezTerm | Nightly portable zip, through the launcher | Latest nightly |

`wslu` provides `wslview`, so browser-based logins (`gh auth login`, Claude Code) open the Windows browser.
Projects pin their own versions through a project `.mise.toml` or `.java-version`, which mise honours automatically.

### 9.1 Switching the default version

The captain wants a quick command to switch the system-wide default version of a tool, starting with Maven.
"System-wide" means the whole WSL2 distribution in v1, and the Windows machine itself once the Windows-native phase exists.

- `use-version <tool> <version>` sets the default version of a mise-managed tool for this machine.
  `mvnuse <version>` and `jdkuse <version>` are shortcuts for Maven and Java.
- Without a version argument, the command lists the installed versions and marks the current default.
- The switch is machine-local and stored under `.local/`, so it never edits the tracked manifest in `config/mise/config.toml` and never changes other machines.
- It takes effect for new shells and for non-interactive callers, because mise resolves the default through its shims.
  The current shell picks it up immediately as well.
- A project's own `.mise.toml` or `.java-version` still wins inside that project.
- The Windows-native phase must provide the same commands with the same names for PowerShell and Git Bash.

## 10. Configuration ownership

| Tool | Repository file | How it is applied |
|---|---|---|
| mise | `config/mise/config.toml` | Symlink at `~/.config/mise/conf.d/devbootstrapper.toml`; `~/.config/mise/config.toml` links to the machine-local `.local/mise/config.toml`, which mise loads with higher precedence (section 9.1); `~/.local/share/mise` links to `tools/mise` |
| git | `config/git/gitconfig` | Symlink at `~/.gitconfig`; includes the context routing generated by `gitid` into `.local/git/` (section 10.1) |
| Maven | `config/maven/settings.xml` (template) | Rendered by `devup` into `.local/maven/settings.xml` with the proxy, mirror and local repository (`tools/cache/m2`); `~/.m2/settings.xml` links to it; credentials stay `${env.*}` references |
| npm | `config/npm/npmrc` (template) | Rendered into `.local/npm/npmrc` with the cache (`tools/cache/npm`) and registry; `~/.npmrc` links to it; the token stays a `${NPM_REGISTRY_TOKEN}` reference |
| Caches | none | `~/.cache` links to `tools/cache`, so caches of programs started without the environment layer land there too |
| tmux | `config/tmux/tmux.conf` | Symlink at `~/.tmux.conf` |
| starship | `config/starship.toml` | `STARSHIP_CONFIG` |
| WezTerm | `config/wezterm/wezterm.lua` | Loaded by the Windows-side stub over `\\wsl.localhost\<distro>\...`, with a minimal built-in fallback when WSL is unreachable |
| Claude Code | `config/claude/settings.json`, `config/claude/CLAUDE.md` | Symlinks into `~/.claude/` (section 14) |

`devup` owns every symlink.
It replaces an existing real file only after backing it up to `tmp/backup-<date>/`.
For files a tool itself rewrites (the Claude Code files and the machine-local mise file), an existing real file is adopted instead: copied into the dev home, then linked, so the change shows up rather than being lost.
Templates exist because Maven and npm cannot ignore an unset variable in a mirror or registry entry; values in `.local/profile.env` that contain shell special characters are written quoted.

### 10.1 Git identities and forge accounts

Any number of forge accounts must be usable side by side, including several accounts on the same forge.
The known starting set is a personal GitHub account, a work GitHub account and a work GitLab account.
Two concepts keep this manageable:

- An account is one login on one forge host.
  It has a name (for example `github-personal`, `github-work`, `gitlab-work`), a host, a username and an authentication method: HTTPS with a token kept in `.secrets`, or SSH with a key file.
- A context is a folder directly under `sources/` (`home`, `work`, and any added later).
  It defines the commit name and email, an optional commit-signing key, and which account to use for each forge host.
  A context may use at most one account per host.

Both are stored in `.local/git/identities.gitconfig`, in git's own config format, so scripts read it with `git config -f`.
It is machine-local because it contains personal email addresses and usernames, and the repository is public.

Resolution, for any git, `gh` or `glab` operation:

1. A repository pinned with `gitid use <context>` uses that context, wherever it lives.
2. Otherwise, a path under `sources/<context>/` uses that context.
3. Otherwise, the machine's default context applies (`work` on the work laptop, `home` on the desktop PC), including for the dev home itself.
4. Within the resolved context, the remote host selects the account.

How it is applied:

- Commit identity: `gitid` generates `includeIf "gitdir:~/development/sources/<context>/"` blocks into `.local/git/routing.gitconfig`, after the machine-default block.
  `gitid use` adds a repository-local include, which takes precedence.
- Authentication: one credential helper (HTTPS) and one SSH command wrapper (SSH), both shipped in the repository, resolve the account from the current directory and the remote host at the moment git asks.
  This also works for `git clone`, where git's folder-based config rules do not yet apply.
- Forge CLIs: `gh` and `glab` are wrapped by small scripts in `bin/wrappers/`, first on PATH, which set `GH_TOKEN` or `GITLAB_TOKEN` (and the host) for the resolved account.
  Interactive shells also define `gh` and `glab` functions that call the wrappers, because `mise activate` puts the real binaries ahead of everything on PATH.
  They work for non-interactive callers too.

The `gitid` command:

- `gitid` shows the resolved context, commit identity and account for the current directory and its remotes.
- `gitid list` shows every account and context.
- `gitid add-account` and `gitid add-context` add entries interactively.
  `add-context` creates the `sources/<context>/` folder, and `add-account` can generate an SSH key and print the public key to register on the forge.
- `gitid use <context>` pins the current repository, and `gitid use --clear` removes the pin.
- `gitid as <account> -- <command>` runs one command as a given account, for example to create a repository on the personal account from anywhere.
- `gitid doctor` checks that every account's token or key is present, and that each context has at most one account per host.

The prompt shows the resolved context inside a repository, so the active identity is always visible.
HTTPS with tokens is the default authentication method, because corporate proxies often block SSH and the `gh` and `glab` CLIs need tokens anyway.
Each account can choose SSH instead, and an SSH account may still have a token for its forge CLI.
`gitid setup` is the guided first-run flow, and `clone <url> [context]` clones into `sources/<context>/` with that context's account.

## 11. Update model

### 11.1 WezTerm

The Start-menu shortcut runs `launcher.ps1`, which:

1. At most once per day, compares the nightly zip's published timestamp or ETag with the last installed one.
2. When newer, downloads it to a staging directory and verifies it.
3. Only if no WezTerm process is running, swaps the staging directory in and keeps the previous version for one rollback.
4. Restores the stub `wezterm.lua` and the local file, then starts `wezterm-gui.exe`.

Downloads use the Windows system proxy with default credentials.

### 11.2 Everything else: `devup`

`devup` runs these steps in order, each idempotent; `--skip` and `--only` select steps:

1. `pull`: `git pull --ff-only` of the dev home.
   If the working tree has local changes or has diverged, it skips the pull and reports instead of stashing or merging.
   After pulling it re-runs the updated `devup`.
2. `windows`: syncs `windows/` assets to the Windows tools folder through `/mnt/c`.
3. `certs`: adds the corporate root certificate to Ubuntu's trust store.
4. `apt`: the apt proxy drop-in, the git-core PPA when it publishes for the installed release, base packages and `apt-get upgrade`, with the user typing the `sudo` password.
5. `render`: renders the Maven and npm templates into `.local/`.
6. `links`: ensures the symlinks from section 10 and the `~/.bashrc` blocks.
7. `mise`: installs or self-updates mise into `tools/bin`, then `mise install`, `mise upgrade` within the version pins and `mise prune` of versions no longer referenced.
8. `certs-java`: imports the corporate root certificate into every installed JDK.
9. `identities`: regenerates the git identity config (`gitid sync`).
10. `completions`: generates bash completions for the installed tools into `tools/completions/`.
11. `doctor`: prints the health report: tool versions, Docker availability, GitHub reachability, links, identities and `.secrets` permissions.

A complete, successful run writes the last-update stamp to `tools/state/last-update`.
`devup --unlink` removes every link and the `~/.bashrc` blocks.

### 11.3 Daily trigger

On the first WezTerm start of a day, `wezterm.lua` (in its `gui-startup` event) records the date in `tools/state/last-daily-prompt` and opens one extra tab running `devup --daily`, so the tab opens at most once per day even when an update fails.
The user sees the output there and types the `sudo` password.
Other terminals get only the reminder from section 8.

### 11.4 Version pinning

Runtimes keep their major or LTS line fixed (Java per LTS, Node `lts`, Maven 3.10 and 4), so updates stay within that line.
CLI tools follow `latest`.
Moving a runtime to a new major version is a deliberate edit of `config/mise/config.toml`.

## 12. Profiles, proxy and certificates

`.local/profile.env` holds `DEV_PROFILE=home|work` plus machine settings: proxy URL, `NO_PROXY`, registry mirror URLs and the path to the corporate root certificate.
Every tool reads its proxy and certificate settings from that one place:

- Environment: `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` and their lowercase forms, for curl, mise, git, npm, uv and pip.
- apt: a drop-in under `/etc/apt/apt.conf.d/` rendered by `devup`.
- Maven: `<proxies>` and `<mirrors>` in `settings.xml`, interpolated from environment variables.
- Java: `JAVA_TOOL_OPTIONS` proxy properties, and the corporate root certificate imported into each installed JDK's trust store by `devup`.
- Node: `NODE_EXTRA_CA_CERTS`.
- Python: `REQUESTS_CA_BUNDLE` and `SSL_CERT_FILE`.
- System: the certificate added to the Ubuntu trust store with `update-ca-certificates`.

With an empty proxy and no certificate configured, all of this is a no-op, which is the home profile.
How the work proxy actually behaves (authentication, PAC file, TLS inspection) is an investigation item (section 18).

## 13. Secrets

- `.secrets` sits at the dev home root, is gitignored and is created with mode 600.
- Its format is `KEY=value` lines, loaded with `set -a`, so the same file also works as a Docker `--env-file`.
- `bootstrap.sh` warns, without printing values, when the file mode is wider than 600.
- `.secrets.example` is tracked and lists every expected key with a comment and no value.
- Configuration files reference secrets only through environment variables, never by value.
- Encryption (for example sops with age, or a password-manager CLI) is a possible later step, not v1.

## 14. Claude Code

- Claude Code comes from mise (section 9), so its updates come from `devup` rather than its own updater.
- `config/claude/settings.json` and `config/claude/CLAUDE.md` hold the captain's cross-project preferences.
  `devup` symlinks them into `~/.claude/`.
- Changes Claude Code writes to `settings.json` therefore show up as a git diff in the dev home, to commit or discard deliberately.
  If a tool replaces the link with a real file, the next `devup` adopts that file into the dev home and relinks it.
- Credentials, history and project state stay in `~/.claude/` and are never tracked.
- Until the work-laptop investigation (section 18) supplies the real contents, the tracked files are placeholders; the first `devup` on a machine with existing Claude Code settings adopts them, for review before committing.

## 15. Portability

- The shell layer (`bash/`) and most of `config/` are plain bash and standard configuration files.
  They work unchanged in WSL under any terminal, such as Windows Terminal; only the daily update tab is WezTerm-specific, and the shell reminder covers that case.
- They also work on native Ubuntu or Debian, including over SSH.
  Windows-only pieces (`wslview`, `/mnt/c` sync, `wsl.conf`) are guarded by WSL detection.
- `devup` is Debian- and Ubuntu-specific because of apt.
  Another Linux distribution would need only a package-manager adapter, because mise itself is distribution-independent.
- The Windows-native side (Git Bash for Windows, PowerShell and Command Prompt) is a different environment: Windows paths, no apt, Windows-native binaries and a different home.
  The WSL installer cannot be reused there.
  It is planned as a later phase with its own install path under `C:\development\`.
  Git Bash can still share `aliases.sh`, `functions.sh`, `prompt.sh` and the git configuration, so v1 must keep those files free of WSL-only assumptions.

## 16. Footprint outside the dev home

Everything outside `~/development`, listed so it can be audited and removed:

- WSL: two marked blocks in `~/.bashrc`; the symlinks from section 10 (including `~/.cache` and `~/.local/share/mise`); `/etc/wsl.conf`; the apt drop-ins for the proxy and the git PPA; the corporate certificate in the system trust store; and the apt packages.
- Windows: `C:\development\tools\wezterm\` and `C:\development\tools\launcher\`, the Start-menu shortcut and, opt-in, `%USERPROFILE%\.wslconfig`.

`docs/getting-started.md` documents uninstall: `devup --unlink` removes the symlinks and the `~/.bashrc` blocks, then delete `~/development`, and the Windows tools folders and shortcut.

## 17. Acceptance criteria

On a fresh Windows machine with WSL2 and Ubuntu:

1. One PowerShell command, plus answering the first-run prompts, ends with WezTerm open in an Ubuntu shell at `~/development`.
2. `java -version` reports 25, `mise ls java` lists every supported LTS, and `mvn`, `node`, `npm`, `ng`, `python`, `uv`, `claude`, `gh`, `tmux` and `docker` all resolve.
3. Every mise-managed tool, and every cache, lives under `~/development/tools/`.
4. A second `devup` run changes nothing and reports success.
5. `git config user.email` differs between a repository in `sources/home/` and one in `sources/work/`, also from a non-interactive shell.
   On the same machine, a clone and push in `sources/home/` uses the personal GitHub account, and one in `sources/work/` uses the work GitHub account.
6. After `.secrets` is filled in and files are added to `tmp/`, `git status` in the dev home stays clean.
7. Interactive shell startup stays under 200 ms.
8. The daily update tab opens at most once per day.
9. The launcher installs a newer WezTerm nightly on the next start after one is published.
10. The work profile installs and updates successfully behind the corporate proxy.
11. Every shell script passes `shellcheck`.
12. `mvn -v` reports 3.10; after `mvnuse 4`, both a new interactive shell and a non-interactive shell report Maven 4, and `mvnuse 3.10` switches back, with no change to tracked files.
13. Outside `sources/`, `git config user.email` returns the work identity on a machine with the work profile and the home identity on one with the home profile.
14. `gitid use`, `gitid as` and the `gh` and `glab` wrappers select the expected account, and a third context added with `gitid add-context` works without editing any tracked file.
15. `dev cheat` lists the commands, aliases, functions and keys, `dev docs` shows every documentation topic, and `dev ids` prints the account table.

## 18. Work-laptop investigation brief

The captain's work laptop has a First Officer checkout and the employer's internal onboarding repository.
That repository was an earlier attempt at this toolkit: a one-time hook setup to get any dev work going, which turned out not to be flexible enough.
A First Officer on that laptop should run a scout covering the points below.
It writes findings to its private report, and feeds back into this spec only generic facts, never internal hostnames, employer details or credentials.

1. The onboarding repository: what it sets up, how it is triggered, which parts are worth reusing, and exactly where it proved too rigid.
2. Corporate proxy: whether it needs authentication (and which kind), whether it uses a PAC file, whether TLS inspection with a corporate root certificate is in place, and whether WSL's `autoProxy` passes it through.
3. Package registries: whether work uses Maven and npm mirrors (Artifactory, Nexus or similar), how authentication is configured today, and whether public registries are blocked.
4. Restrictions on the laptop: PowerShell execution policy, AppLocker or similar, administrator rights, whether WSL and Ubuntu may be installed, and which Ubuntu version is allowed.
5. Current Claude Code user settings and user-level `CLAUDE.md`, as a candidate for `config/claude/`.
6. Java, Maven, Node and Angular versions used across current work projects, to confirm the version policy in section 9, including whether the work builds run on Maven 3.10 and Maven 4.
7. Current git, Maven and npm user configuration, with credentials replaced by placeholders.
8. Which IDE is used and how it reaches the code: IntelliJ on Windows against WSL sources, JetBrains Gateway, VS Code Remote WSL, or something else.
9. What EDI needs from its host beyond tmux, gh and git.
10. Which tools are installed on the laptop today (winget, Chocolatey, Scoop or manual), to catch anything missing from section 9.
11. Whether `C:\development\` exists and can be written without administrator rights, and what it currently contains.
12. Whether SSH to GitHub and to the work GitLab passes the corporate network, how the git accounts authenticate today, and whether the work GitLab is gitlab.com or self-hosted.

## 19. Open questions

None for the captain at this point.
The remaining unknowns are the work-laptop investigation items in section 18; any question they raise is added here, and its answer may change the proxy, certificate, registry and Claude Code defaults that v1 ships as empty hooks.

## 20. Decisions recorded

- Windows is the only host platform for v1, with WSL2 and Ubuntu assumed.
- Ubuntu is the latest stable release available.
  The captain prefers bleeding-edge releases.
  The installer detects and explains a missing WSL or Ubuntu, but does not install them.
- WezTerm runs from the nightly portable zip and is updated by a custom launcher, not Scoop.
- Windows-side files live in `C:\development\tools\`.
  The Windows-native side (Git Bash, PowerShell, Command Prompt) is a later phase, and Git Bash lite mode is not part of v1.
- The DevBootstrapper repository is treated as public.
- The dev home is `~/development`, which is the repository itself, using an allow-list `.gitignore`.
- All mise-managed tools live in `~/development/tools/`, and all caches in `~/development/tools/cache/`.
- `tmp/` exists, is never committed and is never cleaned automatically.
- `.secrets` lives at the dev home root and is never committed.
- The bash setup is modular under `bash/`, entered only through `bootstrap.sh`.
- Shell setup and install/update are separate (`bootstrap.sh` versus `devup`).
- Configurations are applied through environment variables or symlinks, with the full footprint listed in section 16.
- Project checkouts go in `~/development/sources/<context>/`, starting with `home` and `work`; the folder decides the git context, and everywhere else the machine's profile decides.
- Any number of forge accounts is supported, several per forge, managed with `gitid` (section 10.1).
  Accounts are chosen per context and host, can be pinned per repository, and can be used for a single command.
- Java comes from Eclipse Temurin: every supported LTS (8, 11, 17, 21, 25) on every machine, with JDK 25 as the default.
- Maven 3 and Maven 4 are both installed, with the 3.10 line (currently 3.10.0) as the default until the captain says otherwise.
- Switching the default version is one quick command per machine (`mvnuse`, `jdkuse`, `use-version`), with Windows-side equivalents in the later phase.
- npm is the only Node package manager, at home and at work.
- The work profile has a corporate proxy.
- The daily update asks for the `sudo` password in its own tab; there is no passwordless `sudo` rule.
- Default Claude Code user settings are tracked in `config/claude/`.
- First Officer and EDI are not cloned by the toolkit, but their prerequisites (tmux, gh, git) are installed.
- Managing `.wslconfig` is an opt-in installer step.
- There is no Kubernetes tooling.
- All suggested CLI tools from section 9 are included.
- HTTPS with personal access tokens is the default git authentication; SSH is a per-account option.
- A context uses at most one account per forge host.
- The `dev` command provides the overview, cheat sheet, documentation, account table and health report (section 8.1).
- tmux comes from mise, now that mise ships a prebuilt build.
- Work happens directly on DevBootstrapper's default branch.

## 21. Verification status

Verified by the automated tests (`tests/run.sh`), run in a sandboxed home on Ubuntu 24.04 and by CI on every push on the `ubuntu-latest` runner (Ubuntu 26):

- Git contexts and accounts: commit identity per folder and by machine default, also from non-interactive shells; the credential helper per folder and host, including the clone case; the SSH key choice; the `gh` and `glab` wrappers; `gitid use`, `gitid as`, one account per host, a third context, listing and doctor.
- Version switching: `mvnuse`, `jdkuse` and `use-version` write only the machine-local file and keep every version installed.
- Shell and `devup`: the two `~/.bashrc` blocks, environment for `bash -lc`, interactive layer winning over Ubuntu's defaults, silent non-interactive shells, every link with adopt and backup behaviour, idempotent second runs, `--unlink`, template rendering with a work profile, the reminder, the 200 ms startup budget without optional tools, the allow-list `.gitignore` and the pull step.
- The `devup` apt step ran for real against Ubuntu's package manager, including the fallback to Ubuntu's git when the git-core PPA is unreachable.
- All shell scripts pass shellcheck, and the Lua files compile.

Verified by CI (`.github/workflows/ci.yml`) on a Windows runner: the launcher installs WezTerm nightly and places the stub, a second start the same day does not download again, and PSScriptAnalyzer reports no errors in `windows/`.
CI got no runners while the repository was private; it runs since the repository is public.

Not yet verified:

- `install.ps1` end to end on a real Windows machine with WSL: WSL detection, `.wslconfig`, the first run inside WSL, the WSL restart and the shortcut.
- The WezTerm configuration live: WSL domain, keys, the stub loading the repository config over `\\wsl.localhost`, and the daily update tab.
- The `mise` step and the tools it installs, including Maven 3.10 resolving, and `certs-java`.
- Behaviour behind the corporate proxy (section 18).
