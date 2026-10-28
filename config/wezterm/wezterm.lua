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

  -- Appearance. JetBrains Mono and Nerd Font symbols ship with WezTerm.
  config.color_scheme = 'Tokyo Night'
  config.font = wezterm.font_with_fallback { 'JetBrains Mono', 'Symbols Nerd Font Mono' }
  config.font_size = 11.0
  config.use_fancy_tab_bar = false
  config.tab_max_width = 32
  config.scrollback_lines = 20000
  config.audible_bell = 'Disabled'
  config.window_padding = { left = 6, right = 6, top = 4, bottom = 4 }

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
