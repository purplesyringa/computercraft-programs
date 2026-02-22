local named = require "named"
local pack = require "pack"

local args = { ... }
if #args == 0 then
    print("Usage: netbootd <sysroot relative to nfs>")
    return
end

local hostname = named.hostname()
rednet.host("netboot", hostname)

local boot_path = fs.combine("nfs", args[1], "packages", "svc", "boot.lua")
local code = pack.packString(([[
    require "vfs.install"
    local vfs = require "vfs"
    local nfs = require "nfs"
    vfs.unmount("nfs")
    fs.makeDir("nfs")
    nfs.mount("nfs", %q)
    os.run(_ENV, %q, "packages.svc.boot", %q)
]]):format(hostname, boot_path, boot_path))

while true do
    local computer_id, message = rednet.receive("netboot")
    if message == "request" then
        rednet.send(computer_id, code, "netboot")
    end
end
