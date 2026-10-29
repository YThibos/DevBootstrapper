# WezTerm

WezTerm runs from `C:\development\tools\wezterm`.
Next to `wezterm.exe` sits a small stub `wezterm.lua` that loads the real configuration from `~/development/config/wezterm/wezterm.lua` inside WSL, with a minimal WSL-first fallback when WSL is not reachable.
Edits to the real configuration reload automatically.

- New tabs and panes open in your Ubuntu distribution, in `~/development`.
- `Alt+l` opens the launcher with PowerShell and Command Prompt.
- The first start of the day opens the update tab (see [updates.md](updates.md)).
- The look is a soft blue and turquoise palette in Consolas, with JetBrains Mono and Nerd Font symbols (both ship with WezTerm) as fallbacks.
- Font files dropped in `~/development/.local/fonts` are found without installing them in Windows, for example Fira Code for a rule below.

## Backgrounds

The background follows the active pane, from rules in `.local/wezterm.lua` (not in git).
`devup --first-run` copies [.local.example/wezterm.lua](../.local.example/wezterm.lua) there; on an existing install, copy it by hand and adjust it.

- Images are looked up in the Windows Pictures folder, or in the folder `pictures` names; a missing image is skipped.
- The first rule that matches wins: a pane title pattern (`title`), an ssh session (`ssh = true`) or a fragment of the current directory (`cwd`).
- A rule may also set a font and colours, so a pane can change its whole look, such as an agent's session recognised by its title.
- Without a matching rule the `default` image shows; without any image the plain palette shows.
- Edits apply on `Ctrl+Shift+r`.

WezTerm cannot see processes inside WSL, so the shell tells it where it is: [bash/tools/wezterm.sh](../bash/tools/wezterm.sh) sends the current directory (OSC 7) at every prompt and wraps `ssh` to mark the pane while it runs.
Inside tmux both pass through, thanks to `allow-passthrough` in the tmux configuration.

Keys (also in `dev cheat`):

| Key | Action |
|---|---|
| `Alt+Enter` / `Alt+Shift+Enter` | Split pane beside / below |
| `Alt+arrows` | Move between panes |
| `Alt+z` | Zoom pane |
| `Alt+w` | Close pane |
| `Alt+l` | Launcher |
| `Ctrl+Shift+u` | Run devup in a new tab |
| `Ctrl+Shift+r` | Reload the configuration |
