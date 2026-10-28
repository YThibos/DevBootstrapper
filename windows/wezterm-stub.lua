-- DevBootstrapper stub, copied next to wezterm.exe as wezterm.lua by the launcher.
-- It loads the real configuration from the dev home in WSL, and falls back to a minimal
-- WSL-first configuration when that is unreachable. Do not edit this copy.
local wezterm = require 'wezterm'

local function load_machine()
  local ok, machine = pcall(dofile, wezterm.executable_dir .. '\\devboot-local.lua')
  if ok and type(machine) == 'table' then
    return machine
  end
  return {}
end

local machine = load_machine()

if machine.config_path then
  local ok, result = pcall(function()
    local f = assert(io.open(machine.config_path, 'r'))
    f:close()
    wezterm.add_to_config_reload_watch_list(machine.config_path)
    return dofile(machine.config_path).build(machine)
  end)
  if ok then
    return result
  end
  wezterm.log_error('DevBootstrapper: using the fallback configuration: ' .. tostring(result))
end

local config = wezterm.config_builder()
if machine.distro then
  config.default_domain = 'WSL:' .. machine.distro
end
config.check_for_updates = false
return config
