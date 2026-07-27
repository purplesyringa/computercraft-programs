local tableui = require "tableui"

local timings = os._timings

local writeRow = tableui.header({
    { key = "time", heading = "Time", width = 6 },
    { key = "took", heading = "Took", width = 6 },
    { key = "step", heading = "Step" },
})
local prev = 0
for _, timing in pairs(timings) do
    local step, time = table.unpack(timing)
    local took = time - prev
    if took <= 0.05 then
        term.setTextColor(colors.gray)
    elseif took <= 0.25 then
        term.setTextColor(colors.white)
    elseif took <= 0.50 then
        term.setTextColor(colors.yellow)
    else
        term.setTextColor(colors.red)
    end
    writeRow({ time = time, took = took, step = step })
    prev = time
end
