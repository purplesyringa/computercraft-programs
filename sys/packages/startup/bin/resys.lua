local startup = require "startup"

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

local initrd = http.get("https://cc.purplesyringa.moe/initrd.lua")
if not initrd:match("=initrd") then
    printError("Failed to fetch initrd.lua")
    return
end

if initrd == cur_startup then
    print("The system is already up to date")
    return
end

startup.setScript(initrd)
print("Updated startup.lua, restart the computer for changes to take effect")
