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
        ARRIVING_SHORT = "<prib>",
        BOARDING = "<Posadka>",
        BOARDING_SHORT = "<posad>",
        NO_TRAINS = "<Net poezdow>",
        NO_TRAINS_SHORT = "?:??",
        NO_BOARDING_HERE = "<Na |tom puti posadka passavirow ne proizwoditsq>",
    }
else
    return {
        TOWARDS = "tow.",
        ARRIVING = "Arriving",
        ARRIVING_SHORT = "arriv",
        BOARDING = "Boarding",
        BOARDING_SHORT = "now",
        NO_TRAINS = "No trains",
        NO_TRAINS_SHORT = "unk",
        NO_BOARDING_HERE = "No passenger boarding on this track",
    }
end
