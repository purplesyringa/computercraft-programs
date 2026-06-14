local tableui = require "tableui"
term.setTextColor(colors.green)
local writeRow = tableui.header({
    { key = "id", heading = "ID", width = 6 },
    { key = "hostname", heading = "hostname" },
})

rednet.broadcast(nil, "named-request")

local timeout = 5
local finish = os.clock() + timeout

local seen = {}
local hosts = {}

while timeout > 0 do
    local sender, hostname = rednet.receive("named-response", timeout)
    timeout = finish - os.clock()
    if not sender then
        break
    end
    if not seen[sender] then
        seen[sender] = true
        table.insert(hosts, { id = sender, hostname = hostname })
    end
end

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
