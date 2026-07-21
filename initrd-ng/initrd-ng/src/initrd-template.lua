local tree = __TREE__

if mounting then return tree end

local function readFile(path)
    local ptr = tree
    for part in path:gmatch("[^/]+") do
        ptr = ptr and ptr.entries and ptr.entries[part]
    end
    return ptr and ptr.contents
end

local function loadFromTree(name)
    local name_as_path = name:gsub("%.", "/")
    local contents = (
        readFile("packages/" .. name_as_path .. "/init.lua")
        or readFile("packages/" .. name_as_path .. ".lua")
    )
    if contents then
        return load(contents, "=initrd:" .. name, nil, _ENV)
    end
end
table.insert(package.loaders, loadFromTree)

os._timings = {
    { "startup.lua", os._bt or 0 },
    { "initrd unpacked", os.clock() },
}
require "vfs.install"
require("vfs").unmount("sys")
fs.makeDir("sys")
require("tmpfs").mount("sys", tree, true)
os._initrd_tree = tree
shell.run("sys/startup")
