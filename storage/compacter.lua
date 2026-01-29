local async = require "async"
local util = require "util"

local modem = peripheral.find("modem")
assert(modem, "Modem not available")
rednet.open(peripheral.getName(modem))

local crafter = peripheral.find("workbench")
assert(crafter, "Crafting table not available")

os.setComputerLabel("Compacting turtle")

local wired_name = modem.getNameLocal()

local server_id = rednet.CHANNEL_BROADCAST

local index = {} -- Type: { [key] = item, ... }

local INCLUDE_NAMES = {
    ["minecraft:coal"] = true,
    ["minecraft:diamond"] = true,
    ["minecraft:emerald"] = true,
    ["minecraft:redstone"] = true,
    ["minecraft:lapis_lazuli"] = true,
}
local INCLUDE_TAGS = {
    ["c:nuggets"] = true,
    ["c:ingots"] = true,
    ["c:raw_materials"] = true,
    -- ["spectrum:gemstone_powders"] = true, -- Requires pigment pedestal
    ["spectrum:gemstone_shards"] = true,
}
local EXCLUDE_NAMES = {
    ["minecraft:brick"] = true,
    ["minecraft:nether_brick"] = true,
}
local EXCLUDE_TAGS = {}
local CRAFTING_SLOTS = {
    1, 2, 3, -- 4
    5, 6, 7, -- 8
    9, 10, 11, -- 12
    -- 13, 14, 15, 16
}

local inventory_adjusted = async.newNotify()

local function validItem(item)
    if EXCLUDE_NAMES[item.name] then
        return false
    end
    for tag, _ in pairs(item.tags) do
        if EXCLUDE_TAGS[tag] then
            return false
        end
    end
    if INCLUDE_NAMES[item.name] then
        return true
    end
    for tag, _ in pairs(item.tags) do
        if INCLUDE_TAGS[tag] then
            return true
        end
    end
    return false
end

local function filterIndex()
    local filtered_index = {}
    local fast_retry = false
    for _, item in pairs(index) do
        if validItem(item) and item.count > 64 then
            local count = 9 * math.min(64, math.floor((item.count - 32) / 9))
            fast_retry = fast_retry or count == 9 * 64
            table.insert(filtered_index, util.itemWithCount(item, count))
        end
    end
    return fast_retry, filtered_index
end

local function currentInventory()
    return async.parMap(util.iota(16), function(slot)
        return turtle.getItemDetail(slot, true)
    end)
end

local inventory_adjusted = async.newNotify()
local inventory_adjusted_message = nil

local function waitAdjust(goal_inventory)
    while true do
        rednet.send(server_id, {
            type = "adjust_inventory",
            client = wired_name,
            current_inventory = currentInventory(),
            goal_inventory = goal_inventory,
            preview = false,
        }, "purple_storage")

        inventory_adjusted.wait()
        if not inventory_adjusted_message.needs_retry then
            return
        end
    end
end

local function makeGoalOf(item)
    local goal_inventory = {}
    local count = item.count / 9
    for _, slot in pairs(CRAFTING_SLOTS) do
        goal_inventory[slot] = util.itemWithCount(item, count)
    end
    return goal_inventory
end

local function sumCounts(inv)
    local res = 0
    for _, item in pairs(inv) do
        res = res + item.count
    end
    return res
end

async.spawn(function()
    while true do
        local fast_retry, filtered_index = filterIndex()
        for _, item in pairs(filtered_index) do
            waitAdjust(makeGoalOf(item))
            if sumCounts(currentInventory()) ~= item.count then
                fast_retry = true
            else
                crafter.craft()
            end
        end
        waitAdjust({})

        if not fast_retry then
            os.sleep(10)
        end
    end
end)

async.spawn(function()
    while true do
        local computer_id, msg = rednet.receive("purple_storage")
        if msg.type == "inventory_adjusted" then
            server_id = computer_id
            inventory_adjusted_message = msg
            inventory_adjusted.notify()
        elseif msg.type == "patch_index" then
            server_id = computer_id
            if msg.reset then
                index = {}
            end
            for key, item in pairs(msg.items) do
                index[key] = item
            end
        end
    end
end)

rednet.send(server_id, { type = "request_index" }, "purple_storage")

async.drive()
