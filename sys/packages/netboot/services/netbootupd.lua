return {
    description = "Updates netboot script in startup.lua",
    type = "oneshot",
    start = function()
        local vfs = require "vfs"
        local startup = require "startup"
        local svc = require "svc"

        local old_startup = startup.getScript()
        local new_startup = vfs.read(fs.combine(svc.sysroot, "packages", "netboot", "boot.lua"))
        if (
            old_startup
            and #old_startup < 4096 -- don't override unpacked initrd
            and old_startup:match('"=netboot"')
            and old_startup ~= new_startup
        ) then
            startup.setScript(new_startup)
        end
    end,
}
