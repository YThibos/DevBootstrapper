-- Machine WezTerm settings for DevBootstrapper (docs/wezterm.md). Copy to .local/wezterm.lua;
-- .local/ is never committed. WezTerm watches this file and reloads its configuration on a change.

-- The EDI checkout in WSL (~ is the Linux home). Its docs/images/EDI-darkness.jpg is EDI's face.
local edi = '~/EDI'

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
  -- and says which image to show: a name in the pictures folder, a Windows path, a Linux path
  -- (~ is the Linux home), or a list of these of which the first existing file wins.
  -- A rule may also set: brightness (0-1, default 0.20), wash (opacity of the dark layer, default
  -- 0.35), contain (fit the whole image on black), font (a list of families) and colors (over the
  -- palette). A rule whose images all are missing is skipped.
  rules = {
    -- EDI's face while an EDI tmux session (edi-<yymmdd>-<hhmm>) is attached: EDI's wallpaper
    -- when it has made one, otherwise the picture in the EDI checkout.
    {
      title = '^edi%-%d%d%d%d%d%d%-%d%d%d%d',
      image = { '~/.edi/state/wallpaper.png', edi .. '/docs/images/EDI-darkness.jpg' },
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
    -- A folder of your own, for example: { cwd = 'sources/home/stellaris', image = 'nebula.jpg' },
  },
}
