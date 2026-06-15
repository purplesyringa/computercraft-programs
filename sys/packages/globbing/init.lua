local function toPattern(glob)
    -- See https://www.lua.org/manual/5.3/manual.html#6.4.1 for list of magic characters
    local pattern = glob
        :gsub("([]%%^$().[+-])", "%%%1")
        :gsub("%*", ".*") -- any string glob
        :gsub("%?", ".") -- any character glob
    return "^" .. pattern .. "$"
end

return {
    toPattern = toPattern,
}
