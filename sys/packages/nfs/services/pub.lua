return {
    description = "Configures NFS share",
    type = "oneshot",
    start = function()
        local bind = require "bind"
        fs.makeDir("pub/sys")
        bind.mount("sys", "pub/sys", true)
    end,
    stop = function()
        local vfs = require "vfs"
        vfs.unmount("pub/sys")
    end,
}
