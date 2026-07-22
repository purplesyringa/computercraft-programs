return {
    formatRgb = function(rgb)
        if rgb then
            return ("%06x"):format(rgb)
        end
        return "native"
    end,
    stringToList = function(s)
        local palette = {}
        local index = 0
        for rgb in (s .. ","):gmatch("(.-),") do
            rgb = tonumber(rgb, 16)
            if rgb and rgb >= 0 and rgb <= 0xFFFFFF then
                palette[index] = rgb
            end
            index = index + 1
            if index == 16 then break end
        end
        return palette
    end,
    listToString = function(palette)
        local out = {}
        for index = 0, 15 do
            local value = palette[index]
            table.insert(out, value and ("%x"):format(value) or "")
        end
        return table.concat(out, ",")
    end,
    mapToList = function(dict)
        local palette = {}
        for index = 0, 15 do
            palette[index] = dict[2^index]
        end
        return palette
    end,
    listToMap = function(palette)
        local dict = {}
        for index = 0, 15 do
            dict[2^index] = palette[index]
        end
        return dict
    end,
}
