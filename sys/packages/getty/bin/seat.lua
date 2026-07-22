local palettes = require "getty.palettes"
local Seat = require "getty.seat"

local args = { ... }

if #args == 0 then
    printError("Usage:")
    printError("  seat [+seat] reset [--scale|--palette]")
    printError("  seat [+seat] scale [scale|'keep']")
    printError("  seat [+seat] color <index|name> [rgb|'native']")
    return
end

local seat = Seat.current()
if args[1]:sub(1, 1) == "+" then
    seat = Seat.new(args[1]:sub(2))
    table.remove(args, 1)
end
if not seat then
    printError("Not seated!")
    return
end

if args[1] == "reset" then
    if args[2] == nil then
        seat:reset()
    elseif args[2] == "--scale" then
        seat:resetScale()
    elseif args[2] == "--palette" then
        seat:resetPalette(true)
    else
        printError("Unknown reset target")
        return
    end
elseif args[1] == "scale" then
    if args[2] == nil then
        print("default:", seat.defaults:getScale() or "keep")
        print("current:", seat:getScale())
        return
    elseif args[2] == "keep" then
        seat.defaults:setScale(nil)
    else
        local scale = tonumber(args[2])
        if scale then
            seat.defaults:setScale(scale)
            seat:resetScale()
        else
            printError("Non-numeric scale")
            return
        end
    end
elseif args[1] == "color" then
    local color = args[2]
    local index = tonumber(color)
    if index then
        if index < 0 or index > 15 then
            printError("Color index out of bounds")
            return
        end
        color = 2^index
    else
        color = colors[color]
        if type(color) ~= "number" then
            printError("Unknown color")
            return
        end
    end
    local default_palette = seat.defaults:getPaletteMap()
    local palette = seat:getPaletteMap()
    if not args[3] then
        print("default:", palettes.formatRgb(default_palette[color]))
        print("current:", palettes.formatRgb(palette[color]))
        return
    elseif args[3] == "native" then
        default_palette[color] = nil
        palette[color] = nil
    else
        local rgb = tonumber(args[3], 16)
        if not rgb then
            printError("Not a hex number")
            return
        end
        if rgb < 0 or rgb > 0xFFFFFF then
            printError("HDR is not supported")
            return
        end
        default_palette[color] = rgb
        palette[color] = rgb
    end
    seat.defaults:setPaletteMap(defaultPalette)
    seat:setPaletteMap(palette, true)
end
