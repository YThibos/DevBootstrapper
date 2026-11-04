# Shell

## How it loads

devup adds two marked blocks to `~/.bashrc`:

- **Top block** (`bootstrap.sh env`): the environment layer, `bash/env.sh`.
  It runs for every bash shell, including non-interactive login shells such as `bash -lc` (used by WezTerm's update tab and by tools that start shells).
  It loads `.local/profile.env` and `.secrets`, sets PATH (DevBootstrapper commands, then mise tools), points every cache at `tools/cache`, and applies the proxy and certificate settings.
  It prints nothing and never touches the network.
- **Bottom block** (`bootstrap.sh`): the interactive layer, loaded after Ubuntu's own `~/.bashrc` defaults so DevBootstrapper's settings win.
  It sources, in order: `bash/tools/*.sh` (history, mise, git, java, node, docker, fzf, zoxide, wsl), `aliases.sh`, `functions.sh`, `completions.sh`, `prompt.sh`, and finally `bash/local.sh`.

Interactive startup must stay under 200 ms; check with `dev startup-time`, which measures the shell you use.
A plain `bash -c` (non-login, non-interactive) reads no startup files at all; use `bash -lc` when a tool needs the environment.

## zsh, an opt-in

bash stays the default.
Set `DEV_SHELL=zsh` in `.local/profile.env` (the first run asks, and `devup` installs zsh) and the next `devup` switches the machine to zsh:

- `~/.zshenv` gets a block that loads the same environment layer as bash (`bash/env.sh`), so `zsh -lc` and a plain `zsh -c` see the same PATH, proxy, caches, tools and `.secrets` as `bash -lc` does.
- A login zsh also reads `/etc/profile` and `~/.profile`, as a login bash does, so directories such as `~/.local/bin` and `/snap/bin` are on the PATH in both.
- `~/.zshrc` gets a block, at the bottom so it wins over your own settings, that loads the interactive layer in `zsh/`.
- Without the opt-in neither file is ever touched.
  Setting `DEV_SHELL` back to `bash` removes the blocks again, and a file that held nothing else.
- tmux starts the chosen shell as a login shell in every pane (`default-command` in the rendered tmux configuration).
- To make zsh your login shell as well, run `chsh -s "$(command -v zsh)"` once.

The zsh layer reuses what bash has: `bash/tools/` (mise, git, java, node, docker, fzf, zoxide, wsl and the WezTerm integration), `aliases.sh` and `functions.sh`, so `dev`, `clone`, `repo` and every alias work the same.
What is specific to zsh lives in `zsh/`:

| File | What it holds |
|---|---|
| `bootstrap.zsh` | The entry point, `env` for `~/.zshenv` and plain for `~/.zshrc`. |
| `history.zsh` | 50000 lines in `~/.zsh_history`, no duplicates, shared between tabs. |
| `keybindings.zsh` | Emacs keys, and `Ctrl+Left` and `Ctrl+Right` jump a whitespace-delimited word, `Ctrl+Home` and `Ctrl+End` go to the start and end of the whole input, and `Ctrl+Up` and `Ctrl+Down` act as `Up` and `Down`. |
| `completion.zsh` | A menu to select from, case-insensitive matching, results grouped by kind, and completions for `gitid`, `use-version`, `mvnuse`, `jdkuse`, `dev` and `devup`. |
| `prompt.zsh` | The prompt, described below. |
| `local.zsh` | Your own additions for this machine (not in git), loaded last. |

The prompt reads `user(WSL2) ~/dir git:[branch*] $`, and `user(:host) ~/dir $` outside WSL.
The colours run from dark to light teal: the user, the label, the directory and the `git:` frame.
The branch is green when the workspace is clean, yellow with staged or unstaged changes, and red with untracked files.
The git check stops at the first changed file, so the prompt stays fast on `/mnt/c`.

`devup` generates zsh completions for the installed tools into `tools/completions/zsh/` and keeps the completion dump in `tools/cache/zsh/`.
`dev cheat zsh` lists the keys.

## Extending it

- **An alias or function for everyone**: add it to `bash/aliases.sh`, `bash/functions.sh` or the matching `bash/tools/<tool>.sh`.
  Put a `#: usage | description` line right above it and it appears in `dev cheat`.
  These files are read by bash and by zsh, so keep them to what both understand.
- **Something only for this machine**: `bash/local.sh` (not in git), loaded last; `zsh/local.zsh` is its counterpart for zsh.
- **A new tool file**: add `bash/tools/<tool>.sh`, start it with `command -v <tool> >/dev/null 2>&1 || return 0`, and add it to the list in `bash/bootstrap.sh` and in `zsh/bootstrap.zsh`.

Useful functions: `clone <url> [context]`, `repo [query]`, `mkcd`, `tmpd`, `secrets`, `reload`, `port <n>`, `serve`, `extract`.
