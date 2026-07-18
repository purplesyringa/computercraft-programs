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

local function refresh(use_table)
    term.clear()
    term.setCursorPos(1, 1)
    local width, height = term.getSize()
    local est = (use_table and estimation.trainEstimates or estimation.estimates)()
    local wait = 1
    for _, v in ipairs(est) do
        if v.value == estimation.PRESENT then
            v.text = (use_table and locale.BOARDING_SHORT or locale.BOARDING)
            v.color = colors.green
        elseif v.value == estimation.IMMINENT then
            v.text = (use_table and locale.ARRIVING_SHORT or locale.ARRIVING)
            v.color = colors.yellow
        elseif v.value then
            local floor = math.floor(v.value)
            wait = math.min(wait, v.value - floor)
            v.text = ("%2d:%02d"):format((floor-floor%60)/60, floor%60)
        else
            v.text = (use_table and locale.NO_TRAINS_SHORT or locale.NO_TRAINS)
            v.color = colors.red
        end
    end
    if next(est) then
        local dprint = nonWrappingPrint()
        term.setTextColor(colors.gray)
        dprint(locale.TOWARDS)
        for k, v in ipairs(est) do
            term.setTextColor(colors.white)
            local name = ru.text.to_koi(v.name)
            if use_table then
                if v.color then
                    term.setTextColor(v.color)
                end
                local train = ru.text.to_koi(v.train)
                local prefix = (" "):rep(5 - #v.text) .. v.text .. " " .. name .. "  "
                local suffix = (" "):rep(width - #prefix - #train) .. train
                dprint((prefix .. suffix):sub(1, width))
            else
                dprint(name)
                if v.color then
                    term.setTextColor(v.color)
                end
                dprint(v.text)
            end
        end
    else
        term.setTextColor(colors.white)
        print(locale.NO_BOARDING_HERE)
    end
    return wait
end

local function thread(use_table)
    while true do
        local wait = refresh(use_table)
        async.timeout(wait, estimation.waitForUpdates)
    end
end

return {
    thread = thread,
}
