local vfs = require "vfs"
local tableui = require "tableui"

term.setTextColor(colors.green)
local writeRow = tableui.header({
    { key = "root", heading = "Mountpoint", width = 16 },
    { key = "drive", heading = "Drive", width = 8 },
    { key = "description", heading = "Description" },
})

for _, mount in ipairs(vfs.list()) do
    if mount.shadowed then
        term.setTextColor(colors.gray)
    else
        term.setTextColor(colors.white)
    end
    mount.root = "/" .. mount.root
    writeRow(mount)
end
