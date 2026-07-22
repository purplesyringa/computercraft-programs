local expect = require "cc.expect".expect
local palettes = require "getty.palettes"

local Defaults = {}

function Defaults.new(name)
    expect(1, name, "string")
    return setmetatable({ name = name }, { __index = Defaults })
end

function Defaults:getScale()
    local scale = settings.get("getty.scale." .. self.name, nil)
    if type(scale) == "number" and scale % 0.5 == 0 and scale >= 0.5 and scale <= 5 then
        return scale
    end
end

function Defaults:setScale(scale)
    expect(1, scale, "nil", "number")
    settings.set("getty.scale." .. self.name, scale)
    settings.save()
end

function Defaults:getPaletteString()
    return settings.get("getty.palette." .. self.name, "")
end

function Defaults:getPaletteList()
    return palettes.stringToList(self:getPaletteString())
end

function Defaults:getPaletteMap()
    return palettes.listToMap(self:getPaletteList())
end

function Defaults:setPaletteString(palette)
    settings.set("getty.palette." .. self.name, palette)
    settings.save()
end

function Defaults:setPaletteList(palette)
    self:setPaletteString(palettes.listToString(palette))
end

function Defaults:setPaletteMap(palette)
    self:setPaletteList(palettes.mapToList(palette))
end

return Defaults
