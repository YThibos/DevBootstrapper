# Shell

## How it loads

devup adds two marked blocks to `~/.bashrc`:

- **Top block** (`bootstrap.sh env`): the environment layer, `bash/env.sh`.
  It runs for every bash shell, including non-interactive login shells such as `bash -lc` (used by WezTerm's update tab and by tools that start shells).
  It loads `.local/profile.env` and `.secrets`, sets PATH (DevBootstrapper commands, then mise tools), points every cache at `tools/cache`, and applies the proxy and certificate settings.
  It prints nothing and never touches the network.
- **Bottom block** (`bootstrap.sh`): the interactive layer, loaded after Ubuntu's own `~/.bashrc` defaults so DevBootstrapper's settings win.
  It sources, in order: `bash/tools/*.sh` (history, mise, git, java, node, docker, fzf, zoxide, wsl), `aliases.sh`, `functions.sh`, `completions.sh`, `prompt.sh`, and finally `bash/local.sh`.

Interactive startup must stay under 200 ms; check with `dev startup-time`.
A plain `bash -c` (non-login, non-interactive) reads no startup files at all; use `bash -lc` when a tool needs the environment.

## Extending it

- **An alias or function for everyone**: add it to `bash/aliases.sh`, `bash/functions.sh` or the matching `bash/tools/<tool>.sh`.
  Put a `#: usage | description` line right above it and it appears in `dev cheat`.
- **Something only for this machine**: `bash/local.sh` (not in git), loaded last.
- **A new tool file**: add `bash/tools/<tool>.sh`, start it with `command -v <tool> >/dev/null 2>&1 || return 0`, and add it to the list in `bash/bootstrap.sh`.

Useful functions: `clone <url> [context]`, `repo [query]`, `mkcd`, `tmpd`, `secrets`, `reload`, `port <n>`, `serve`, `extract`.
