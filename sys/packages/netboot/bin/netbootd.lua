local bind = require "bind"
local pack = require "pack"
local vfs = require "vfs"

vfs.unmount("pub/sys") -- clean up after a previous netbootd process
fs.makeDir("pub/sys")
bind.mount("sys", "pub/sys", true)

local boot_path = "nfs/sys/packages/svc/boot.lua"
local code = pack.packString(([[
    require "vfs.install"
    local vfs = require "vfs"
    local nfs = require "nfs"
    vfs.unmount("nfs")
    fs.makeDir("nfs")
    nfs.mount("nfs", %q)
    os.run(_ENV, %q, "packages.svc.boot", %q)
]]):format(os.computerID(), boot_path, boot_path))

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
    end
end
