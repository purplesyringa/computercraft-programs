local async = require "async"
local bind = require "bind"
local pack = require "pack"
local vfs = require "vfs"

vfs.unmount("pub/sys") -- clean up after a previous netbootd process
fs.makeDir("pub/sys") -- create unconditionally as a mountpoint for tmpfs

local code = ([[
    local id, boot_path = %q, %q
]]):format(os.computerID(), "nfs/sys/packages/svc/boot.lua")

code = code .. [[
    os._timings = {
        { "startup.lua", os._bt or 0 },
        { "netboot response", os.clock() },
    }
    require "vfs.install"
    require("vfs").unmount("nfs")
    fs.makeDir("nfs")
    require("nfs").mount("nfs", id)
]]
if os._initrd_tree then
    code = code .. [[
        local _, tree, _ = rednet.receive("netboot-response-initrd")
        table.insert(os._timings, { "initrd response", os.clock() })
        os._initrd_tree = tree
        require("tmpfs").mount("nfs/sys", tree, true)
    ]]
else
    bind.mount("sys", "pub/sys", true)
end
code = code .. [[
    os.run(_ENV, boot_path, "packages.svc.boot", boot_path)
]]

local code = pack.packString(code)

local function reply(channel)
    rednet.send(channel, code, "netboot-response")
    if os._initrd_tree then
        rednet.send(channel, os._initrd_tree, "netboot-response-initrd")
    end
end

-- There might already be devices waiting for startup.
peripheral.find("modem", function(side)
    pcall(rednet.open, side)
end)
reply(rednet.CHANNEL_BROADCAST)

-- Both netbootd and a netboot client can be brought up before a connection between them is
-- estabilished.
async.subscribe("peripheral", function(name)
    if name:match("^computer_") or name:match("^turtle_") then
        local computer_id = peripheral.call(name, "getID")
        if computer_id then
            reply(computer_id)
        end
    end
    if peripheral.hasType(name, "modem") then
        pcall(rednet.open, name)
        reply(rednet.CHANNEL_BROADCAST)
    end
end)

async.spawn(function()
    while true do
        reply(rednet.receive("netboot-request"))
    end
end)

async.drive()
