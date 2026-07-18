local async = require "async"
local estimation = require "metropanel.estimation"
local locale = require "metropanel.locale"
local ru = require "ru"

local function nonWrappingPrint()
    local y = 1
    local _, h = term.getSize()
    return function(x)
        if y == h then
            write(x)
        elseif y < h then
            print(x)
        end
        y = y + 1
    end
end

local function refresh()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    local est = estimation.estimates()
    local wait = 1
    for k, v in ipairs(est) do
        if v.value == estimation.PRESENT then
            v.value = locale.BOARDING
            v.color = colors.green
        elseif v.value == estimation.IMMINENT then
            v.value = locale.ARRIVING
            v.color = colors.yellow
        elseif v.value then
            local floor = math.floor(v.value)
            wait = math.min(wait, v.value - floor)
            v.value = ("%2d:%02d"):format((floor-floor%60)/60, floor%60)
        else
            v.value = locale.NO_TRAINS
            v.color = colors.red
        end
    end
    if next(est) then
        local dprint = nonWrappingPrint()
        term.setTextColor(colors.gray)
        dprint(locale.TOWARDS)
        for k, v in ipairs(est) do
            term.setTextColor(colors.white)
            dprint(ru.text.to_koi(v.name))
            if v.color then
                term.setTextColor(v.color)
            end
            dprint(v.value)
        end
    else
        term.setTextColor(colors.white)
        print(locale.NO_BOARDING_HERE)
    end
    return wait
end

local function thread()
    while true do
        local wait = refresh()
        async.timeout(wait, estimation.waitForUpdates)
    end
end

return {
    thread = thread,
}
