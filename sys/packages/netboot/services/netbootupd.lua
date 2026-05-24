return {
    description = "Updates netboot script in startup.lua",
    type = "oneshot",
    start = function()
        local vfs = require "vfs"
        local svc = require "svc"

        local old_startup = svc.getStartupScript()
        local new_startup = vfs.read(fs.combine(svc.sysroot, "packages", "netboot", "boot.lua"))
        if (
            old_startup
            and #old_startup < 4096 -- don't override unpacked initrd
            and old_startup:match('"=netboot"')
            and old_startup ~= new_startup
        ) then
            svc.setStartupScript(new_startup)
        end
    end,
}
