local routes = require "metropanel.routes"
local ru = require "ru"

local function toKOI8(table)
    for k, v in pairs(table) do
        table[k] = ru.text.to_koi(v)
    end
    return table
end

if routes.ownStation().russian then
    return toKOI8 {
        TOWARDS = "<w storonu stancii>",
        ARRIVING = "<Pribytie>",
        BOARDING = "<Posadka>",
        NO_TRAINS = "<Net poezdow>",
        NO_BOARDING_HERE = "<Na |tom puti posadka passavirow ne proizwoditsq>",
    }
else
    return {
        TOWARDS = "tow.",
        ARRIVING = "Arriving",
        BOARDING = "Boarding",
        NO_TRAINS = "No trains",
        NO_BOARDING_HERE = "No passenger boarding on this track",
    }
end
