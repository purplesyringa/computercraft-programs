local impure = require "runfs.impure"
local runfs = require "runfs.fs"
local vfs = require "vfs"

return {
    getImpure = impure.get,
    setImpure = impure.set,
    mount = function(path)
        vfs.mount(path, runfs)
    end,
}
