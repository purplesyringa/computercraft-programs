local this_path = string.sub(debug.getinfo(1, "S").source, 3)
local entry = "/" .. fs.getDir(this_path) .. "/?/init.lua"

local caller_env = debug.getfenv(debug.getinfo(2).func)
caller_env.package.path = entry .. ";" .. caller_env.package.path

