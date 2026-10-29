-- Machine WezTerm settings for DevBootstrapper (docs/wezterm.md). Copy to .local/wezterm.lua;
-- .local/ is never committed. Changes apply when WezTerm reloads its configuration (Ctrl+Shift+r).
return {
  -- Folder holding the images; a name below may also be a full path such as 'C:/images/x.jpg'.
  -- Default: the Windows Pictures folder of the current user.
  -- pictures = 'C:/Users/me/Pictures',

  -- Shown when no rule matches. A missing image is skipped silently.
  default = 'andromeda-darker.jpg',

  -- The first rule that matches the active pane wins. Each rule matches on one of:
  --   title = '<Lua pattern>'  the pane title, such as the session name an agent sets
  --   ssh = true               an ssh session (the ssh wrapper in bash/tools/wezterm.sh)
  --   cwd = '<text>'           a fragment of the current directory, case-insensitive
  -- and may set: brightness (0-1, default 0.20), wash (opacity of the dark layer, default 0.35),
  -- contain (fit the whole image on black), font (a list of families) and colors (over the palette).
  rules = {
    {
      title = '^edi%-%d%d%d%d%d%d',
      image = 'edi-darkness.jpg',
      contain = true,
      brightness = 0.32,
      wash = 0.28,
      font = { 'Fira Code', 'JetBrains Mono' },
      colors = {
        foreground = '#35aab6',
        cursor_bg = '#00d8e8',
        cursor_border = '#00d8e8',
        cursor_fg = '#001a1e',
        selection_bg = '#0e3b42',
        selection_fg = '#d6f6fa',
      },
    },
    { ssh = true, image = 'forkbomb.jpg' },
    { cwd = 'firstofficer', image = 'firstmate.jpg' },
    { cwd = 'development/sources', image = 'lady-justitia.jpg' },
  },
}
