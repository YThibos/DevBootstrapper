-- Loads config/wezterm/wezterm.lua against a stand-in for the wezterm module, so the key table,
-- the tab prompt and the background rules can be checked without WezTerm (tests/test_wezterm_config.sh).
-- Usage: lua5.4 wezterm_harness.lua REPO HOME MODE [ARGUMENT]
--   keys            one line per key: MODS+KEY ACTION ARGUMENT, or for a callback key what it does in order
--   face TITLE      the image, font and text colour WezTerm switches to for a pane with that title
--   prompt NAME     the tab that answering the Ctrl+t prompt with NAME opens, or "ignored"
--   prompt-text     the Ctrl+t prompt's text; HARNESS_TMUX_SESSIONS holds what tmux lists, unset
--                   when WSL does not answer
--   startup         the command of the window WezTerm opens at start
--   font-size       the terminal's font size
--   reload CHANGE   whether WezTerm reloads after CHANGE (none, or local: .local/wezterm.lua is
--                   written) once the check interval has passed
local repo, home, mode, argument = arg[1], arg[2], arg[3], arg[4]

-- The config reads Windows paths with backslashes; here they are ordinary Linux paths.
local real_open, real_dofile = io.open, dofile
io.open = function(path, ...) return real_open((path:gsub('\\', '/')), ...) end
dofile = function(path) return real_dofile((path:gsub('\\', '/'))) end

local handlers = {}
local spawned = {}
local clock = 1000
os.time = function() return clock end
local steps = {}
local fake = {
  home_dir = '/no/windows/home',
  config_builder = function() return {} end,
  default_wsl_domains = function() return { { name = 'WSL:Ubuntu' } } end,
  font_with_fallback = function(families) return { families = families } end,
  action_callback = function(callback) return { action = 'Callback', callback = callback } end,
  on = function(event, handler) handlers[event] = handler end,
  log_info = function() end,
  run_child_process = function(args)
    local listed = os.getenv('HARNESS_TMUX_SESSIONS')
    if not listed then return false, '', 'no WSL' end
    return true, (listed:gsub('|', '\n')), ''
  end,
  sleep_ms = function(ms) steps[#steps + 1] = 'pause ' .. ms .. 'ms' end,
  mux = {
    spawn_window = function(command)
      spawned.command = command
      return nil, nil, { spawn_tab = function() end }
    end,
  },
}
fake.action = setmetatable({}, {
  __index = function(_, name)
    return setmetatable({ action = name }, { __call = function(_, value) return { action = name, arg = value } end })
  end,
})
package.loaded['wezterm'] = fake

local function show(value)
  if type(value) == 'table' then
    local parts = {}
    for _, item in ipairs(value) do parts[#parts + 1] = show(item) end
    return table.concat(parts, ' ')
  end
  return (tostring(value):gsub('%c', function(c) return '^' .. string.char(c:byte() + 64) end))
end

local machine = { distro = 'Ubuntu', dev_home = home .. '/development', dev_home_unc = home .. '/development' }
local config = real_dofile(repo .. '/config/wezterm/wezterm.lua').build(machine)

-- What a callback key does, in order: the actions it performs and the pauses between them.
local function performed(callback)
  steps = {}
  local window = {
    perform_action = function(_, action) steps[#steps + 1] = action.action .. ' ' .. show(action.arg) end,
  }
  callback(window, {})
  return table.concat(steps, ' | ')
end

if mode == 'keys' then
  for _, key in ipairs(config.keys) do
    local action = key.action
    local shown = action.action == 'Callback' and performed(action.callback) or action.action .. ' ' .. show(action.arg)
    print(string.format('%s+%s %s', key.mods, key.key, shown))
  end
elseif mode == 'face' then
  local handler = handlers['update-status']
  local pane = {
    get_title = function() return argument end,
    get_current_working_dir = function() return nil end,
    get_user_vars = function() return {} end,
    get_domain_name = function() return 'WSL:Ubuntu' end,
    get_foreground_process_name = function() return '' end,
  }
  local window = {
    window_id = function() return 1 end,
    perform_action = function() end,
    set_config_overrides = function(_, overrides)
      for _, layer in ipairs(overrides.background or {}) do
        if layer.source.File then print('image=' .. layer.source.File:gsub('\\', '/')) end
      end
      if overrides.font then print('font=' .. show(overrides.font.families)) end
      if overrides.colors then print('foreground=' .. overrides.colors.foreground) end
    end,
  }
  handler(window, pane)
elseif mode == 'prompt' or mode == 'prompt-text' then
  for _, key in ipairs(config.keys) do
    if key.key == 't' and key.mods == 'CTRL' then
      local window = {
        perform_action = function(_, action)
          spawned[#spawned + 1] = action
          print(string.format('%s domain=%s %s', action.action, action.arg.domain.DomainName, show(action.arg.args)))
        end,
      }
      local prompt
      key.action.callback({ perform_action = function(_, action) prompt = action end }, {})
      if mode == 'prompt-text' then
        print(prompt.arg.description)
      else
        local before = #spawned
        prompt.arg.action.callback(window, {}, argument ~= '' and argument or nil)
        if #spawned == before then print('ignored') end
      end
    end
  end
elseif mode == 'startup' then
  handlers['gui-startup'](nil)
  print(show(spawned.command.args))
elseif mode == 'font-size' then
  print(config.font_size)
elseif mode == 'reload' then
  local actions = {}
  local window = {
    window_id = function() return 1 end,
    perform_action = function(_, action) actions[#actions + 1] = action.action end,
    set_config_overrides = function() end,
  }
  local pane = { get_title = function() return '' end, get_user_vars = function() return {} end,
    get_current_working_dir = function() return nil end, get_domain_name = function() return 'WSL:Ubuntu' end,
    get_foreground_process_name = function() return '' end }
  if argument == 'local' then
    local f = assert(real_open(home .. '/development/.local/wezterm.lua', 'a'))
    f:write('\n-- changed\n')
    f:close()
  end
  local handler = handlers['update-status']
  handler(window, pane)
  local early = #actions
  clock = clock + 5
  handler(window, pane)
  handler(window, pane)
  print('before the interval: ' .. early .. ', after: ' .. table.concat(actions, ' '))
end
