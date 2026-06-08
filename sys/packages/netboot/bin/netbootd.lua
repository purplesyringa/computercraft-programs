local bind = require "bind"
local pack = require "pack"
local vfs = require "vfs"

vfs.unmount("pub/sys") -- clean up after a previous netbootd process
fs.makeDir("pub/sys") -- create unconditionally as a mountpoint for tmpfs

local code = [[
    require "vfs.install"
    require("vfs").unmount("nfs")
    fs.makeDir("nfs")
    require("nfs").mount("nfs", %q)
]]
if os._initrd_tree then
    code = code .. [[
        local _, tree, _ = rednet.receive("netboot-response-initrd")
        os._initrd_tree = tree
        require("tmpfs").mount("nfs/sys", tree, true)
    ]]
else
    bind.mount("sys", "pub/sys", true)
end
code = code .. [[
    os.run(_ENV, %q, "packages.svc.boot", %q)
]]

local boot_path = "nfs/sys/packages/svc/boot.lua"
local code = pack.packString(code:format(os.computerID(), boot_path, boot_path))

-- There might already be devices waiting for startup.
rednet.broadcast(code, "netboot-response")

while true do
    local computer_id

    parallel.waitForAny(function()
        computer_id = rednet.receive("netboot-request")
    end, function()
        -- Both netbootd and a netboot client can be brought up before a connection between them is
        -- estabilished.
        local _, name = os.pullEvent("peripheral")
        if name:match("^computer_") or name:match("^turtle_") then
            computer_id = peripheral.call(name, "getID")
        end
    end)

    if computer_id then
        rednet.send(computer_id, code, "netboot-response")
        if os._initrd_tree then
            rednet.send(computer_id, os._initrd_tree, "netboot-response-initrd")
        end
    end
end
