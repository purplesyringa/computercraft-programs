local expect = require "cc.expect".expect
local Defaults = require "getty.defaults"
local palettes = require "getty.palettes"
local hardware = require "hardware"

local Seat = {}

function Seat.new(name)
    expect(1, name, "string")
    local self = setmetatable({ defaults = Defaults.new(name) }, { __index = Seat })

    if name == "default" then
        self.names = { monitor = "default", keyboard = "default" }
    else
        self.names = hardware.resolveGroup(self.defaults.name)
    end
    assert(self.names.monitor, self.defaults.name .. ".monitor is undefined")

    if self.names.monitor == "default" then
        self.monitor = term.native()
    else
        self.monitor = peripheral.wrap(self.names.monitor)
    end
    assert(self.monitor, "monitor " .. self.names.monitor .. " is not connected")

    return self
end

function Seat.current()
    return term._seat
end

function Seat:getScale()
    return self.monitor and self.monitor.getTextScale and self.monitor.getTextScale()
end

function Seat:setScale(scale)
    if self.monitor and self.monitor.setTextScale and scale then
        self.monitor.setTextScale(scale)
    end
end

function Seat:resetScale()
    self:setScale(self.defaults:getScale())
end

function Seat:getPaletteString(show_native)
    return self.monitor and palettes.listToString(self:getPaletteList(show_native))
end

function Seat:getPaletteList(show_native)
    if not self.monitor then
        return nil
    end
    local palette = {}
    for index = 0, 15 do
        local current = colors.packRGB(self.monitor.getPaletteColor(2^index))
        local native = colors.packRGB(term.nativePaletteColor(2^index))
        if show_native or current ~= native then
            palette[index] = current
        end
    end
    return palette
end

function Seat:getPaletteMap(show_native)
    return self.monitor and palettes.listToMap(self:getPaletteList(show_native))
end

function Seat:setPaletteString(palette, apply_current)
    self:setPaletteList(palettes.stringToList(palette), apply_current)
end

function Seat:setPaletteList(palette, apply_current)
    for index = 0, 15 do
        local color = palette[index]
        if not color then
            color = colors.packRGB(term.nativePaletteColor(2^index))
        end
        if self.monitor then
            self.monitor.setPaletteColor(2^index, color)
        end
        if apply_current then
            term.setPaletteColor(2^index, color)
        end
    end
end

function Seat:setPaletteMap(palette, apply_current)
    self:setPaletteList(palettes.mapToList(palette), apply_current)
end

function Seat:resetPalette(apply_current)
    self:setPaletteString(self.defaults:getPaletteString(), apply_current)
end

function Seat:reset(apply_current)
    self:resetScale()
    self:resetPalette(apply_current)
end

return Seat
