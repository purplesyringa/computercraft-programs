local globbing = require "globbing"
local named = require "named"
local tableui = require "tableui"

local args = { ... }
local pattern = globbing.toPattern(args[1] or "*")
local hosts = named.collect(pattern)

if not next(hosts) then
    printError("Nothing found")
    return
end

term.setTextColor(colors.green)
local writeRow = tableui.header({
    { key = "id", heading = "ID", width = 6 },
    { key = "hostname", heading = "hostname" },
})

table.sort(hosts, function(a, b)
    return a.id < b.id
end)

for _, d in ipairs(hosts) do
    if d.hostname then
        term.setTextColor(colors.white)
    else
        term.setTextColor(colors.gray)
        d.hostname = "unset"
    end
    writeRow(d)
end
