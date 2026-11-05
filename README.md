# DevBootstrapper

A portable, self-updating development toolkit: one repository that turns any Windows machine with WSL2 into the same Java, Maven, Angular and agent-tooling environment, at home and at work.
After a one-command install everything happens inside WezTerm, and the toolkit keeps WezTerm and every tool up to date.
Every WezTerm tab is a tmux session, bash is the default shell, and zsh with the themed prompt is an opt-in (`DEV_SHELL=zsh`).

## Install

Prerequisites: Windows 10 or 11, WSL2 with an Ubuntu distribution (the installer explains how to get it if missing), and optionally Docker Desktop with WSL integration.

In PowerShell (no administrator rights needed):

```powershell
irm https://raw.githubusercontent.com/YThibos/DevBootstrapper/main/windows/install.ps1 | iex
```

The installer sets up WezTerm under `C:\development\tools`, clones this repository into `~/development` inside WSL, and runs a short interactive first setup (machine profile, proxy, git identities).
See [docs/getting-started.md](docs/getting-started.md).

## Daily use

| Command | What it does |
|---|---|
| `dev` | Overview of the toolkit |
| `dev cheat [filter]` | Cheat sheet: commands, aliases, functions, WezTerm and tmux keys |
| `dev docs [topic]` | This documentation, in the terminal |
| `devup` | Update everything (also runs automatically once a day from WezTerm) |
| `gitid` / `dev ids` | Which git identity and account apply here / all accounts and contexts |
| `mvnuse 4`, `jdkuse 21` | Switch this machine's default Maven or JDK |
| `clone <url> [context]` | Clone into `sources/<context>/` with the right account |

## Layout

```
~/development/
├── bash/       shell setup, entered through bootstrap.sh
├── zsh/        the opt-in zsh layer: prompt, keys, completion
├── bin/        dev, devup, gitid, use-version, mvnuse, jdkuse and git helpers
├── config/     tool configuration: mise manifest, git, Maven, npm, tmux, starship, WezTerm, Claude
├── docs/       documentation (dev docs)
├── install/    devup, doctor, apt package list
├── lib/        shared shell libraries
├── windows/    Windows installer, WezTerm launcher and config stub
├── sources/    your project checkouts, one folder per git context (home/, work/, ...)
├── tools/      every installed tool and every cache (not in git)
├── tmp/        scratch space (not in git)
├── .local/     this machine's settings: profile, proxy, git identities (not in git)
└── .secrets    credentials (not in git)
```

## Documentation

- [Getting started](docs/getting-started.md) - install and first run
- [Uninstall](docs/uninstall.md) - a full reset for a fresh install, or removing DevBootstrapper but keeping Ubuntu
- [Shell](docs/shell.md) - how the bash setup loads, the zsh opt-in, and how to extend it
- [Tools and versions](docs/tools.md) - where each tool comes from, adding tools, switching versions
- [Git identities](docs/identities.md) - several accounts per forge with gitid
- [Updates](docs/updates.md) - devup, the daily update, WezTerm updates and rollback
- [Network](docs/network.md) - work profile, corporate proxy, certificates, mirrors
- [Secrets](docs/secrets.md) - the .secrets file
- [WezTerm](docs/wezterm.md) - tabs as tmux sessions, keys, backgrounds and EDI's face
- [Specification](SPEC.md) - the agreed design
