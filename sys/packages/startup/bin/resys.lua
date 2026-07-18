local startup = require "startup"

local args = { ... }
if #args == 1 and args[1] == "--help" then
    printError("Usage:")
    printError("  resys [channel]")
end
local channel = args[1] or "cc.purplesyringa.moe"

local cur_startup = startup.getScript()
if not cur_startup then
    printError("startup.lua is missing, cannot update")
    return
end

if #cur_startup < 4096 and cur_startup:match('"=netboot"') then
    printError("startup.lua is a netboot client, update the system on the fileserver instead")
    return
end

if not cur_startup:match('"=initrd"') then
    printError("startup.lua has unknown type, cannot update")
    return
end

local response, error = http.get("https://" .. channel .. "/initrd.lua")
if not response then
    printError("Failed to fetch initrd.lua: " .. error)
    return
end

local initrd = response.readAll()
if not initrd:match("=initrd") then
    printError("Corrupted initrd.lua fetched")
    return
end

if initrd == cur_startup then
    print("The system is already up to date")
    return
end

startup.setScript(initrd)
print("Updated startup.lua, restart the computer for changes to take effect")
