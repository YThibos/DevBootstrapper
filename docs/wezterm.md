# WezTerm

WezTerm runs from `C:\development\tools\wezterm`.
Next to `wezterm.exe` sits a small stub `wezterm.lua` that loads the real configuration from `~/development/config/wezterm/wezterm.lua` inside WSL, with a minimal WSL-first fallback when WSL is not reachable.
Edits to the real configuration reload within a few seconds (see below: the configuration checks its own files, as WezTerm cannot watch inside WSL).

- New tabs open in your Ubuntu distribution, in `~/development`.
- `Alt+Shift+l` opens the launcher with PowerShell and Command Prompt.
- The first start of the day opens the update tab (see [updates.md](updates.md)).
- The look is a soft blue and turquoise palette in Consolas, with JetBrains Mono and Nerd Font symbols (both ship with WezTerm) as fallbacks.
- Font files in `~/development/.local/fonts` are found without installing them in Windows.
  `devup` puts Fira Code (SIL Open Font License) there, the `fonts` step, for EDI's face below; a second run downloads nothing.

## Tabs are tmux sessions

A WezTerm tab is a tmux session, and splits and windows inside a tab are tmux panes and windows, never WezTerm splits.
The first window of WezTerm opens the session `main`, and `Ctrl+t` asks for a name and opens that session in a new tab, creating it when it does not exist.
Closing a tab only detaches it: the session and everything running in it carry on, and `Ctrl+t` with the same name brings it back.
Names may hold letters, digits, `_` and `-`.

The keys inside a tab type tmux's prefix (`Ctrl-b`) and a command into the focused pane, through tmux's command prompt.
That runs in the tmux server, so no second tmux client starts inside the first and every command hits the pane you are looking at.
Tabs opened any other way, such as from the launcher, are plain shells, where these keys do nothing useful.

The tmux configuration (`config/tmux/tmux.conf`, rendered by `devup` into `.local/tmux/tmux.conf` and linked from `~/.tmux.conf`) keeps the default prefix, lets the shell talk to WezTerm (`allow-passthrough`) and starts your shell as a login shell in every pane (`default-command`, bash or the zsh you opted in to, see [shell.md](shell.md)).

## Backgrounds and EDI's face

The background follows the active pane, from rules in `.local/wezterm.lua` (not in git).
When it is missing, `devup` creates it from [.local.example/wezterm.lua](../.local.example/wezterm.lua) (the `links` step); it never overwrites your copy.

- An image is a file in the Windows Pictures folder, or in the folder `pictures` names, a Windows path, a Linux path (`~` is your Linux home), or a list of these of which the first existing file wins.
- A rule whose images are all missing is skipped without a message.
- The first rule that matches wins: a pane title pattern (`title`), an ssh session (`ssh = true`) or a fragment of the current directory (`cwd`).
  Inside tmux the title is the session name: the tmux configuration turns `set-titles` on for every session.
- A rule may also set a font and colours, so a pane can change its whole look, such as an agent's session recognised by its title.
- EDI's face is such a rule: while a tmux session named `edi-<yymmdd>-<hhmm>` is attached, the pane shows Fira Code in dark cyan text, a bright cyan cursor and a deep teal selection, over a black underlay with the picture fitted whole on top.
  The picture is `~/.edi/state/wallpaper.png` when EDI has made one, otherwise `docs/images/EDI-darkness.jpg` in the EDI checkout.
  The checkout is `~/EDI`; change `local edi = '~/EDI'` at the top of `.local/wezterm.lua` when yours lives elsewhere.
  With neither file the rule is skipped and the pane keeps its usual look.
  WezTerm picks the picture when it loads its configuration, so press `Ctrl+Shift+r` once after either file first appears.
  A `.local/wezterm.lua` from before EDI's face moved to the EDI checkout keeps its old rule; `devup` warns about it until you copy the EDI rule from the example.
- `font_size` sets this machine's font size (default 11.0), for a large, dense screen.
- Without a matching rule the `default` image shows; without any image the plain palette shows.
- Edits to `.local/wezterm.lua` reload within a few seconds, and so does the file's first appearance. WezTerm's own file watch cannot see inside WSL, so the configuration checks its files every three seconds.

WezTerm cannot see processes inside WSL, so the shell tells it where it is: [bash/tools/wezterm.sh](../bash/tools/wezterm.sh) sends the current directory (OSC 7) at every prompt and wraps `ssh` to mark the pane while it runs.
The next prompt clears the mark, also after an ssh that was interrupted before it returned.
Inside tmux both pass through, thanks to `allow-passthrough` in the tmux configuration.

Keys (also in `dev cheat`):

| Key | Action |
|---|---|
| `Ctrl+t` | New tab: asks for a name, opens that tmux session |
| `Alt+1` ... `Alt+0` | Switch to tab 1 ... 10, another tmux session |
| `Alt+Enter` / `Alt+Shift+Enter` | Split the tmux pane beside / below |
| `Alt+h` / `Alt+j` / `Alt+k` / `Alt+l` | Move to the tmux pane on the left / below / above / on the right |
| `Ctrl+Shift+w` | Close the tmux pane (`Ctrl+w` stays the shell's word erase) |
| `Ctrl+n` | New tmux window |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tmux window |
| `Alt+Shift+n` | Break the tmux pane out into its own window |
| `Alt+z` | Zoom the tmux pane, again to restore the layout |
| `Alt+c` | tmux copy mode, to scroll and search the pane's own history |
| `Alt+Shift+l` | Launcher |
| `Ctrl+Shift+u` | Run devup in a new tab |
| `Ctrl+Shift+r` | Reload the configuration |
