local async = require "async"
local routes = require "metropanel.routes"
local db = require "metropanel.db"

local train_last_seen = {}
local train_last_seen_proleptic = {}
local train_route = {}
local route_to_station_cache = db.get("route_to_station_cache", {})
local known_nexts = db.get("known_nexts", {})

local function routeToKey(route, station)
    local ans = routes.stationsToString(route)
    if station then
        ans = ans .. routes.stationToString(station)
    end
    return ans
end

local function addTime(train, route, station)
    train_route[train] = route
    local key = routeToKey(route, station)
    if not train_last_seen[train] then
        return route_to_station_cache[key]
    end
    local old = route_to_station_cache[key]
    local new = os.clock() - train_last_seen[train]
    if old then
        new = 0.2 * new + 0.8 * old
    end
    route_to_station_cache[key] = new
    db.save()
    return new
end

local update_event = async.newNotifyOne()
async.subscribe("train_imminent", update_event.notifyOne)

async.subscribe("train_arrival", function()
    local train = routes.trainName()
    local stations = routes.trainStations()
    local own = routes.ownStation()
    addTime(train, stations, own)
    train_last_seen[train] = os.clock()
    train_last_seen_proleptic[train] = os.clock()
    rednet.broadcast({
        train = train,
        route = stations,
        station = own,
    }, "metropanel-train-arrival")
    update_event.notifyOne()
end)

async.subscribe("train_departure", update_event.notifyOne)

async.subscribe("rednet_message", function(sender, pkt, proto)
    if proto == "metropanel-train-arrival" then
        local t = addTime(pkt.train, pkt.route, pkt.station)
        if t then
            train_last_seen_proleptic[pkt.train] = os.clock() - t
        end
        update_event.notifyOne()
    end
end)

local IMMINENT = -1
local PRESENT = -2

local function getTrainEstimates()
    local estimates_by_train = {}
    local own = routes.ownStation()
    for train, t in pairs(train_last_seen_proleptic) do
        local sinceSeen = os.clock() - t
        local route = train_route[train]
        if route then
            local key = routeToKey(route, own)
            local rtt = route_to_station_cache[key]
            if rtt then
                local next = routes.nextStation(route)
                if next then
                    local value = nil
                    if rtt >= sinceSeen then
                        value = rtt - sinceSeen
                    end
                    estimates_by_train[train] = {
                        name = next.name,
                        value = value,
                        train = train,
                    }
                end
            end
        end
    end
    if routes.trainPresent() then
        local current_train = routes.trainName()
        local current_next = routes.nextStation(routes.trainStations())
        if current_next then
            local q = estimates_by_train[current_train]
            if not q then
                q = {
                    name = current_next.name,
                    train = current_train,
                }
                estimates_by_train[current_train] = q
            end
            q.value = PRESENT
        end
    end
    local estimates_by_train_list = {}
    for _, v in pairs(estimates_by_train) do
        if not known_nexts[v.name] then
            known_nexts[v.name] = true
            db.save()
        end
        table.insert(estimates_by_train_list, v)
    end
    table.sort(estimates_by_train_list, function(a, b)
        if b.value then
            return a.value and a.value < b.value
        else
            return a.value
        end
    end)
    if next(estimates_by_train_list) and estimates_by_train_list[1].value ~= PRESENT and routes.trainImminent() then
        estimates_by_train_list[1].value = IMMINENT
    end
    return estimates_by_train_list
end

local function getEstimates()
    local estimates_by_train = getTrainEstimates()
    local estimates_by_dst = {}
    local seen_nexts = {}
    for _, v in ipairs(estimates_by_train) do
        if not seen_nexts[v.name] then
            seen_nexts[v.name] = true
            table.insert(estimates_by_dst, v)
        end
    end
    for k, _ in pairs(known_nexts) do
        if not seen_nexts[k] then
            table.insert(estimates_by_dst, { name = k, value = nil, train = nil })
        end
    end
    return estimates_by_dst
end

return {
    estimates = getEstimates,
    trainEstimates = getTrainEstimates,
    waitForUpdates = update_event.wait,
    IMMINENT = IMMINENT,
    PRESENT = PRESENT,
}
