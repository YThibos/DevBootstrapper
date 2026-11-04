-- DevBootstrapper WezTerm configuration (docs/wezterm.md).
-- Loaded by the stub next to wezterm.exe, which passes the machine values written by install.ps1:
--   distro, dev_home (Linux path), dev_home_unc (Windows path to the same folder).
-- Returns a function so the stub can hand those values in.
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

-- tmux's own prefix, Ctrl-b, as the raw byte WezTerm types into the focused pane.
local TMUX_PREFIX = string.char(2)
-- How long tmux gets to open its command prompt before the command is typed into it.
local TMUX_PROMPT_OPEN_MS = 50

-- Today's date as the update stamp format used by devup.
local function today()
  return os.date('%Y-%m-%d')
end

-- True once per day: records today's date in tools/state/last-daily-prompt.
local function daily_update_due(machine)
  if not machine.dev_home_unc then
    return false
  end
  local path = machine.dev_home_unc .. '\\tools\\state\\last-daily-prompt'
  local f = io.open(path, 'r')
  if f then
    local last = f:read('*l')
    f:close()
    if last == today() then
      return false
    end
  end
  f = io.open(path, 'w')
  if not f then
    -- The state folder does not exist before the first devup run.
    return false
  end
  f:write(today() .. '\n')
  f:close()
  return true
end

-- Soft blue and turquoise: Tiffany Blue (#0abab5) and Turquoise Blue (#3fc7c1) lead, slightly
-- desaturated so text stays readable over a dimmed background image.
local PALETTE = {
  foreground = '#c6e4ea',
  background = '#0b1418',
  cursor_bg = '#0abab5',
  cursor_fg = '#08191c',
  cursor_border = '#0abab5',
  selection_bg = '#2f6d78',
  selection_fg = '#eaf6f8',
  ansi = { '#16262c', '#c97b84', '#7fb7a6', '#d9c98c', '#5b8fd6', '#9a8fcf', '#3fc7c1', '#cfe3e8' },
  brights = { '#3a5560', '#dda0a7', '#9fd4c2', '#e8dcae', '#7fb0e0', '#b3a6e0', '#72d3cf', '#eaf6f8' },
}

-- The machine's own wezterm settings, .local/wezterm.lua in the dev home (example in
-- .local.example/wezterm.lua); an empty table when there is none.
local function load_local(machine)
  if not machine.dev_home_unc then
    return {}
  end
  local ok, result = pcall(dofile, machine.dev_home_unc .. '\\.local\\wezterm.lua')
  if ok and type(result) == 'table' then
    return result
  end
  return {}
end

local function file_exists(path)
  local f = io.open(path, 'r')
  if f then
    f:close()
    return true
  end
  return false
end

-- The Linux home folder, which is where the installer puts the dev home (install.ps1).
local function linux_home(machine)
  return machine.dev_home and machine.dev_home:match('^(.*)/development$')
end

-- A Linux path such as ~/EDI as a Windows path through the share that serves the dev home, or
-- nil when this machine does not say where WSL lives.
local function windows_path_of(machine, linux_path)
  if not (machine.dev_home and machine.dev_home_unc) then
    return nil
  end
  local home = linux_home(machine)
  if linux_path:find('^~/') then
    if not home then
      return nil
    end
    linux_path = home .. linux_path:sub(2)
  end
  local share = machine.dev_home_unc:sub(1, #machine.dev_home_unc - #machine.dev_home)
  return share .. linux_path:gsub('/', '\\')
end

-- A dimmed photo with a dark wash on top; 'contain' fits the whole image on a black canvas.
local function layers(path, rule)
  local image = {
    source = { File = path },
    horizontal_align = 'Center',
    vertical_align = 'Middle',
    hsb = { brightness = rule.brightness or 0.20, hue = 1.0, saturation = 1.0 },
  }
  local result = {}
  if rule.contain then
    image.width, image.height = 'Contain', 'Contain'
    image.repeat_x, image.repeat_y = 'NoRepeat', 'NoRepeat'
    table.insert(result, { source = { Color = '#000000' }, width = '100%', height = '100%' })
  end
  table.insert(result, image)
  table.insert(result, { source = { Color = '#000000' }, width = '100%', height = '100%', opacity = rule.wash or 0.35 })
  return result
end

local function cwd_of(pane)
  local cwd = pane:get_current_working_dir()
  if not cwd then
    return ''
  end
  local path = type(cwd) == 'userdata' and (cwd.file_path or tostring(cwd)) or tostring(cwd)
  return path:lower():gsub('\\', '/')
end

-- An ssh session, signalled by the ssh wrapper in bash/tools/wezterm.sh (WezTerm cannot see
-- processes inside WSL), by an SSH domain or by a native ssh process.
local function is_ssh(pane)
  local vars = pane:get_user_vars()
  if vars.ssh_active and vars.ssh_active ~= '' then
    return true
  end
  if (pane:get_domain_name() or ''):lower():find('^ssh') then
    return true
  end
  local proc = (pane:get_foreground_process_name() or ''):lower()
  return proc:find('[/\\]ssh%.?e?x?e?$') ~= nil
end

local function matches(rule, pane)
  if rule.title then
    return (pane:get_title() or ''):find(rule.title) ~= nil
  end
  if rule.ssh then
    return is_ssh(pane)
  end
  if rule.cwd then
    return cwd_of(pane):find(rule.cwd:lower(), 1, true) ~= nil
  end
  return false
end

-- Context-aware backgrounds: the first rule in .local/wezterm.lua that matches the active pane
-- picks the image, and may also set a font and colours; otherwise the default image shows.
local function backgrounds(config, machine)
  local settings = load_local(machine)
  local pictures = settings.pictures or (wezterm.home_dir .. '/Pictures')
  local function locate(name)
    if name:find('^%a:') then
      return name
    end
    if name:find('^[~/]') then
      return windows_path_of(machine, name)
    end
    return pictures .. '/' .. name
  end
  -- An image is one name, or a list of names of which the first existing file wins. A name is a
  -- file in the pictures folder, a Windows path, or a Linux path (~ is the Linux home).
  local function resolve(image)
    for _, name in ipairs(type(image) == 'table' and image or { image }) do
      local path = locate(name)
      if path and file_exists(path) then
        return path
      end
    end
    return nil
  end
  local default = { image = settings.default and resolve(settings.default) }
  local rules = {}
  for _, rule in ipairs(settings.rules or {}) do
    local copy = {}
    for k, v in pairs(rule) do
      copy[k] = v
    end
    copy.image = rule.image and resolve(rule.image)
    if copy.image then
      table.insert(rules, copy)
    end
  end
  if not default.image and #rules == 0 then
    return
  end
  if default.image then
    config.background = layers(default.image, default)
  end

  local function overrides(rule)
    local result = {}
    if rule.image then
      result.background = layers(rule.image, rule)
    end
    if rule.font then
      result.font = wezterm.font_with_fallback(rule.font)
    end
    if rule.colors then
      local colors = {}
      for k, v in pairs(PALETTE) do
        colors[k] = v
      end
      for k, v in pairs(rule.colors) do
        colors[k] = v
      end
      result.colors = colors
    end
    return result
  end

  local shown = {}
  wezterm.on('update-status', function(window, pane)
    local chosen = default
    for _, rule in ipairs(rules) do
      if matches(rule, pane) then
        chosen = rule
        break
      end
    end
    local id = window:window_id()
    if shown[id] ~= chosen then
      shown[id] = chosen
      window:set_config_overrides(overrides(chosen))
    end
  end)
end

-- The command of a tab that is a tmux session: attach to the session NAME, creating it when it
-- does not exist. The login shell brings the toolkit's PATH, where tmux lives; without tmux the
-- tab is a plain shell.
local function tmux_session_args(name)
  local script = 'command -v tmux >/dev/null 2>&1 && exec tmux new-session -A -s ' .. name
    .. '; exec "${DEV_SHELL:-bash}" -l'
  return { 'bash', '-lc', script }
end

-- A key that runs a tmux command in the focused pane's own tmux, through the command prompt
-- (prefix + ':'). The command runs in the tmux server, so nothing starts a nested tmux client
-- and it always targets the pane in focus.
-- tmux opens the prompt only after it has read the prefix and ':', and drops whatever arrived
-- with them, so the command follows once the prompt is open.
local function tmux(command)
  return wezterm.action_callback(function(window, pane)
    window:perform_action(act.SendString(TMUX_PREFIX .. ':'), pane)
    wezterm.sleep_ms(TMUX_PROMPT_OPEN_MS)
    window:perform_action(act.SendString(command .. '\r'), pane)
  end)
end

-- Ctrl+t: asks for a name and opens that tmux session in a new tab. Names are limited to
-- characters tmux accepts in a session name, which also keeps them from injecting commands.
local function new_session_prompt(domain)
  return act.PromptInputLine {
    description = 'New tmux session name:',
    action = wezterm.action_callback(function(window, pane, name)
      if not name or not name:match('^[%w_%-]+$') then
        return
      end
      window:perform_action(
        act.SpawnCommandInNewTab { domain = { DomainName = domain }, args = tmux_session_args(name) },
        pane
      )
    end),
  }
end

-- The key model: a WezTerm tab is a tmux session, and splits and screens inside a tab are tmux
-- panes and windows (docs/wezterm.md).
local function tmux_keys(domain)
  local keys = {
    --: Ctrl+t | new tab: asks for a name, opens that tmux session
    { key = 't', mods = 'CTRL', action = new_session_prompt(domain) },
    --: Alt+Enter / Alt+Shift+Enter | split the tmux pane beside / below
    { key = 'Enter', mods = 'ALT', action = tmux('split-window -h') },
    { key = 'Enter', mods = 'ALT|SHIFT', action = tmux('split-window -v') },
    --: Alt+h / j / k / l | move between tmux panes
    { key = 'h', mods = 'ALT', action = tmux('select-pane -L') },
    { key = 'j', mods = 'ALT', action = tmux('select-pane -D') },
    { key = 'k', mods = 'ALT', action = tmux('select-pane -U') },
    { key = 'l', mods = 'ALT', action = tmux('select-pane -R') },
    --: Ctrl+Shift+w | close the tmux pane (Ctrl+w stays readline's word erase)
    { key = 'w', mods = 'CTRL|SHIFT', action = tmux('kill-pane') },
    --: Ctrl+n | new tmux window
    { key = 'n', mods = 'CTRL', action = tmux('new-window') },
    --: Ctrl+Tab / Ctrl+Shift+Tab | next / previous tmux window
    { key = 'Tab', mods = 'CTRL', action = tmux('next-window') },
    { key = 'Tab', mods = 'CTRL|SHIFT', action = tmux('previous-window') },
    --: Alt+Shift+n | break the tmux pane out into its own window
    { key = 'N', mods = 'ALT|SHIFT', action = tmux('break-pane') },
    --: Alt+z | zoom the tmux pane, again to restore the split layout
    { key = 'z', mods = 'ALT', action = tmux('resize-pane -Z') },
    --: Alt+c | tmux copy mode: scroll and search this pane's own history
    { key = 'c', mods = 'ALT', action = tmux('copy-mode') },
  }
  --: Alt+1 .. Alt+0 | switch to tab 1 .. 10, that is another tmux session
  for tab = 1, 10 do
    table.insert(keys, { key = tostring(tab % 10), mods = 'ALT', action = act.ActivateTab(tab - 1) })
  end
  return keys
end

function M.build(machine)
  machine = machine or {}
  local config = wezterm.config_builder()
  local distro = machine.distro or 'Ubuntu'
  local domain = 'WSL:' .. distro

  -- WSL as the default domain, starting in the dev home.
  local wsl = wezterm.default_wsl_domains()
  for _, d in ipairs(wsl) do
    if d.name == domain and machine.dev_home then
      d.default_cwd = machine.dev_home
    end
  end
  config.wsl_domains = wsl
  config.default_domain = domain

  -- Appearance: a soft blue and turquoise palette, Consolas with JetBrains Mono and Nerd Font
  -- symbols (both ship with WezTerm) as fallbacks. Fonts dropped in .local/fonts are found too.
  config.font = wezterm.font_with_fallback { 'Consolas', 'JetBrains Mono', 'Symbols Nerd Font Mono' }
  config.font_size = 11.0
  if machine.dev_home_unc then
    config.font_dirs = { machine.dev_home_unc .. '\\.local\\fonts' }
  end
  config.colors = PALETTE
  config.use_fancy_tab_bar = false
  config.hide_tab_bar_if_only_one_tab = true
  config.tab_max_width = 32
  config.scrollback_lines = 20000
  config.audible_bell = 'Disabled'
  config.initial_cols = 120
  config.initial_rows = 32
  config.window_padding = { left = 8, right = 8, top = 6, bottom = 6 }

  backgrounds(config, machine)

  -- The DevBootstrapper launcher owns WezTerm updates.
  config.check_for_updates = false

  -- Windows shells stay one keypress away (launcher menu).
  config.launch_menu = {
    { label = 'PowerShell', domain = { DomainName = 'local' }, args = { 'powershell.exe', '-NoLogo' } },
    { label = 'Command Prompt', domain = { DomainName = 'local' }, args = { 'cmd.exe' } },
  }

  config.keys = tmux_keys(domain)
  --: Alt+Shift+l | launcher: WSL, PowerShell, Command Prompt
  table.insert(config.keys, { key = 'L', mods = 'ALT|SHIFT', action = act.ShowLauncher })
  --: Ctrl+Shift+u | run devup in a new tab
  table.insert(config.keys, {
    key = 'u',
    mods = 'CTRL|SHIFT',
    action = act.SpawnCommandInNewTab { args = { 'bash', '-lc', 'devup; exec "${DEV_SHELL:-bash}" -l' } },
  })
  --: Ctrl+Shift+r | reload this configuration
  table.insert(config.keys, { key = 'r', mods = 'CTRL|SHIFT', action = act.ReloadConfiguration })

  -- First start of the day: one extra tab runs the daily update.
  wezterm.on('gui-startup', function(cmd)
    local _, _, window = wezterm.mux.spawn_window(cmd or { args = tmux_session_args('main') })
    if daily_update_due(machine) then
      window:spawn_tab { args = { 'bash', '-lc', 'devup --daily; exec "${DEV_SHELL:-bash}" -l' } }
    end
  end)

  return config
end

return M
