local async = require "async"
local util = require "storage.util"

local modem = assert(peripheral.find("modem"), "Modem not available")
rednet.open(peripheral.getName(modem))
os.setComputerLabel("Compacting turtle")
local wired_name = modem.getNameLocal()
local server_id = rednet.CHANNEL_BROADCAST

local crafter = assert(peripheral.find("workbench"), "Crafting table not available")

local rr = assert(peripheral.find("recipe_registry"), "Recipe registry not available")
local ir = assert(peripheral.find("informative_registry"), "Informative registry not available")

local recipes = rr.list("minecraft:crafting")

-- like { ["minecraft:iron_nugget"] = "minecraft:iron_ingot" }
local nine_to_one = {}
local one_to_nine = {}
local four_to_one = {}
local one_to_four = {}

local function tile_to_items(tile)
    if tile.type == "empty" then
        -- pass
    elseif tile.item then
        coroutine.yield(tile.item)
    elseif tile.tag then
        local items = ir.describe("itemTags", tile.tag) or {}
        for _, item in pairs(items) do
            coroutine.yield(item)
        end
    else
        for _, nested in pairs(tile) do
            tile_to_items(nested)
        end
    end
end

local function process_recipe(recipe)
    -- sanity checks
    assert(recipe.type == "crafting")
    assert(#recipe.output == 1)

    local input = recipe.input
    local output = recipe.output[1]

    local category = nil
    if #input == 9 and recipe.extra and recipe.extra.height == 3 and output.count == 1 then
        category = nine_to_one
    elseif #input == 4 and recipe.extra and recipe.extra.height == 2 and output.count == 1 then
        category = four_to_one
    elseif #input == 1 then
        if output.count == 9 then
            category = one_to_nine
        elseif output.count == 4 then
            category = one_to_four
        end
    end

    if not category or output.nbt then
        return
    end

    local materials = {}
    for _, tile in pairs(recipe.input) do
        for item in coroutine.wrap(function() tile_to_items(tile) end) do
            materials[item] = (materials[item] or 0) + 1
        end
    end

    for material, count in pairs(materials) do
        if count == #input then
            if category[material] and category[material] ~= output.name then
                category[material] = "!ambiguous"
            else
                category[material] = output.name
            end
        end
    end
end

for _, recipe_id in pairs(recipes) do
    process_recipe(rr.get(recipe_id))
end

local function filter_roundtrip(left_to_right, right_to_left)
    for left, right in pairs(left_to_right) do
        if left ~= right_to_left[right] then
            left_to_right[left] = nil
        end
    end
end

-- filter out ambiguous decrafting recipes
for one, _ in pairs(one_to_nine) do
    if one_to_four[one] then
        one_to_four[one] = nil
        one_to_nine[one] = nil
    end
end

filter_roundtrip(nine_to_one, one_to_nine)
filter_roundtrip(one_to_nine, nine_to_one)
filter_roundtrip(four_to_one, one_to_four)
filter_roundtrip(one_to_four, four_to_one)

local index = {} -- Type: { [key] = item, ... }
local index_updated = async.newNotifyWaiters()
local incremental_index = {}

local CRAFTING_SLOTS = {
    [1] = { 1 },
    [4] = { 1, 2, 5, 6 },
    [9] = {
        1, 2, 3, -- 4
        5, 6, 7, -- 8
        9, 10, 11, -- 12
        -- 13, 14, 15, 16
    },
}

local KEEP_LOW = 96
local KEEP_HIGH = 128

local function currentInventory()
    return async.parMap(util.iota(16), function(slot)
        return turtle.getItemDetail(slot, true)
    end)
end

local inventory_adjusted = async.newNotifyWaiters()
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

local function makeGoalOf(item, rounded, recipe_size)
    item = util.itemWithCount(item, rounded)
    local goal = {}
    for _, slot in pairs(CRAFTING_SLOTS[recipe_size]) do
        goal[slot] = item
    end
    return goal
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
        local my_index = incremental_index
        incremental_index = {}
        for _, item in pairs(my_index) do
            local packed = nine_to_one[item.name] or four_to_one[item.name]
            if packed then
                local recipe_size = nine_to_one[item.name] and 9 or 4
                -- index may not have packed, so maxCount needs to be queried from elsewhere
                local max_packed_count = ir.describe("item", packed).maxCount

                -- does not contaminate incremental_index and therefore is never sent to server
                index[packed] = index[packed] or { name = packed, count = 0 }

                -- adjust to KEEP_LOW: craft this item away
                while item.count > KEEP_HIGH do
                    local count = math.min(
                        item.maxCount,
                        16 * max_packed_count,
                        math.floor((item.count - KEEP_LOW) / recipe_size)
                    )
                    item.count = item.count - recipe_size * count
                    index[packed].count = index[packed].count + count
                    waitAdjust(makeGoalOf(item, count, recipe_size))
                    if sumCounts(currentInventory()) ~= count then
                        break
                    end
                    crafter.craft()
                end
            end

            local unpacked = one_to_nine[item.name] or one_to_four[item.name]
            if unpacked then
                local recipe_size = one_to_nine[item.name] and 9 or 4
                local max_unpacked_count = ir.describe("item", unpacked).maxCount
                index[unpacked] = index[unpacked] or { name = unpacked, count = 0 }

                -- adjust to KEEP_HIGH: uncraft packed items
                while index[unpacked].count < KEEP_LOW do
                    local count = math.min(
                        item.maxCount,
                        item.count,
                        math.floor(
                            math.min(
                                16 * max_unpacked_count,
                                KEEP_HIGH - index[unpacked].count
                            ) / recipe_size
                        )
                    )
                    item.count = item.count - count
                    index[unpacked].count = index[unpacked].count + count * recipe_size
                    waitAdjust(makeGoalOf(item, count, 1))
                    if sumCounts(currentInventory()) ~= count * recipe_size then
                        break
                    end
                    crafter.craft()
                end
            end
        end
        waitAdjust({})
        index_updated.wait()
    end
end)

async.spawn(function()
    while true do
        local computer_id, msg = rednet.receive("purple_storage")
        if msg.type == "inventory_adjusted" then
            server_id = computer_id
            inventory_adjusted_message = msg
            inventory_adjusted.notifyWaiters()
        elseif msg.type == "patch_index" then
            server_id = computer_id
            if msg.reset then
                index = {}
                incremental_index = {}
            end
            for key, item in pairs(msg.items) do
                index[key] = item
                incremental_index[key] = item
            end
            index_updated.notifyWaiters()
        end
    end
end)

rednet.send(server_id, { type = "request_index" }, "purple_storage")

async.drive()
