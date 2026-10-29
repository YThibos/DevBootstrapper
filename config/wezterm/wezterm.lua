-- DevBootstrapper WezTerm configuration (docs/wezterm.md).
-- Loaded by the stub next to wezterm.exe, which passes the machine values written by install.ps1:
--   distro, dev_home (Linux path), dev_home_unc (Windows path to the same folder).
-- Returns a function so the stub can hand those values in.
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

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
  local function resolve(name)
    if not name then
      return nil
    end
    local path = name:find('^%a:') and name or (pictures .. '/' .. name)
    return file_exists(path) and path or nil
  end
  local default = { image = resolve(settings.default) }
  local rules = {}
  for _, rule in ipairs(settings.rules or {}) do
    local copy = {}
    for k, v in pairs(rule) do
      copy[k] = v
    end
    copy.image = resolve(rule.image)
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

  config.keys = {
    --: Alt+l | launcher: WSL, PowerShell, Command Prompt
    { key = 'l', mods = 'ALT', action = act.ShowLauncher },
    --: Alt+Enter | split pane beside
    { key = 'Enter', mods = 'ALT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
    --: Alt+Shift+Enter | split pane below
    { key = 'Enter', mods = 'ALT|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
    --: Alt+arrows | move between panes
    { key = 'LeftArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Left' },
    { key = 'RightArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Right' },
    { key = 'UpArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Up' },
    { key = 'DownArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Down' },
    --: Alt+w | close pane
    { key = 'w', mods = 'ALT', action = act.CloseCurrentPane { confirm = true } },
    --: Alt+z | zoom pane
    { key = 'z', mods = 'ALT', action = act.TogglePaneZoomState },
    --: Ctrl+Shift+u | run devup in a new tab
    {
      key = 'u',
      mods = 'CTRL|SHIFT',
      action = act.SpawnCommandInNewTab { args = { 'bash', '-lc', 'devup; exec bash -l' } },
    },
    --: Ctrl+Shift+r | reload this configuration
    { key = 'r', mods = 'CTRL|SHIFT', action = act.ReloadConfiguration },
  }

  -- First start of the day: one extra tab runs the daily update.
  wezterm.on('gui-startup', function(cmd)
    local _, _, window = wezterm.mux.spawn_window(cmd or {})
    if daily_update_due(machine) then
      window:spawn_tab { args = { 'bash', '-lc', 'devup --daily; exec bash -l' } }
    end
  end)

  return config
end

return M
