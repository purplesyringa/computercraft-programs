local hostname = require "hostname"
local tableui = require "tableui"

local function toPattern(glob)
    -- See https://www.lua.org/manual/5.3/manual.html#6.4.1 for list of magic characters
    local pattern = glob
        :gsub("([]%%^$().[+-])", "%%%1")
        :gsub("%*", ".*") -- any string glob
        :gsub("%?", ".") -- any character glob
    return "^" .. pattern .. "$"
end

local args = { ... }
local pattern = toPattern(args[1] or "*")
local hosts = hostname.collect(pattern)

if #hosts == 0 then
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
