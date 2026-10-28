# WezTerm

WezTerm runs from `C:\development\tools\wezterm`.
Next to `wezterm.exe` sits a small stub `wezterm.lua` that loads the real configuration from `~/development/config/wezterm/wezterm.lua` inside WSL, with a minimal WSL-first fallback when WSL is not reachable.
Edits to the real configuration reload automatically.

- New tabs and panes open in your Ubuntu distribution, in `~/development`.
- `Alt+l` opens the launcher with PowerShell and Command Prompt.
- The first start of the day opens the update tab (see [updates.md](updates.md)).
- JetBrains Mono and Nerd Font symbols ship with WezTerm; no font install is needed.

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
