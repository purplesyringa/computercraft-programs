local station = assert(peripheral.find("Create_Station"), "no station?")

local function deglobStation(station_name)
    local ans = ""
    local i = 1
    local parentheses = {}
    while i <= #station_name do
        local c = station_name:sub(i, i)
        if c == "\\" then
            ans = ans .. station_name:sub(i+1, i+1)
            i = i + 2
        elseif c == "{" then
            table.insert(parentheses, false)
            i = i + 1
        elseif c == "," and #parentheses > 0 then
            parentheses[#parentheses] = true
            i = i + 1
        elseif c == "}" then
            table.remove(parentheses)
            i = i + 1
        elseif not parentheses[#parentheses] then
            ans = ans .. c
            i = i + 1
        else
            i = i + 1
        end
    end
    return ans
end

local function parseStation(station_name)
    local flags = {}
    local name, f = station_name:match("^(.*) :([^ ]*)$")
    if name == nil then
        flags.name = station_name
        return flags
    end
    for i in f:gmatch("[^:]+") do
        if i == "r" then
            flags.russian = true
        elseif i == "s" then
            flags.proper_stop = true
        elseif i == "t" then
            flags.no_passthrough = true
        elseif i == "0" or i:match("^[1-9][0-9]*$") then
            flags.discriminator = tonumber(i)
        end
    end
    flags.name = name
    return flags
end

local function trainStations(schedule)
    if not schedule then
        schedule = station.getSchedule()
    end
    local stations = {}
    for _, i in ipairs(schedule.entries) do
        if i.instruction.id == "create:destination" then
            table.insert(stations, parseStation(deglobStation(i.instruction.data.text)))
        end
    end
    return stations
end

local function ownStation()
    return parseStation(station.getStationName())
end

local function nextStation(stations)
    local own = ownStation()
    for i=1,#stations do
        if stations[i].name == own.name and stations[i].discriminator == own.discriminator then
            if not stations[i].proper_stop then
                return nil
            end
            local j = i
            while true do
                j = j % #stations + 1
                if stations[j].proper_stop then
                    return stations[j]
                elseif stations[j].no_passthrough then
                    return nil
                end
            end
        end
    end
    return nil
end

local function stationToString(station)
    local ans = station.name
    if station.discriminator then
        ans = ans .. " :" .. tostring(station.discriminator)
    end
    return ans
end

local function stationsToString(stations)
    local ans = ""
    for _, i in ipairs(stations) do
        ans = ans .. stationToString(i) .. "\n"
    end
    return ans
end

return {
    ownStation = ownStation,
    trainImminent = station.isTrainImminent,
    trainPresent = station.isTrainPresent,
    trainName = station.getTrainName,
    trainStations = trainStations,
    nextStation = nextStation,
    stationToString = stationToString,
    stationsToString = stationsToString,
}
