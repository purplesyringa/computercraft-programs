local hoppers = { peripheral.find("minecraft:hopper") }
local barrels = { peripheral.find("minecraft:barrel") }
local chest = peripheral.find("minecraft:chest")

local local_name = peripheral.find("modem").getNameLocal()

local function count(slots)
    local count = 0
    for _, slot in pairs(slots) do
        count = count + slot.count
    end
    return count
end

local function pullIntoInventory(slots, count, turtle_slot)
    for i = #slots, 1, -1 do
        local slot = slots[i]
        local to_pull = math.min(count, slot.count)
        if to_pull > 0 then
            count = count - to_pull
            slot.count = slot.count - to_pull
            slot.inventory.pushItems(local_name, slot.slot, to_pull, turtle_slot)
        end
    end
end

local function craftingStep()
    local cobblestone = {}
    local quartz = {}
    local gold_nuggets = {}
    for _, inventory in pairs(hoppers) do
        for slot, item in pairs(inventory.list()) do
            local info = { inventory = inventory, slot = slot, count = item.count }
            if item.name == "minecraft:cobblestone" then
                table.insert(cobblestone, info)
            elseif item.name == "minecraft:quartz" then
                table.insert(quartz, info)
            elseif item.name == "minecraft:gold_nugget" then
                table.insert(gold_nuggets, info)
            end
        end
    end

    turtle.select(1)

    local n_recipes = math.floor(math.min(count(cobblestone) / 2, count(quartz) / 4, 32))
    pullIntoInventory(cobblestone, n_recipes, 1)
    pullIntoInventory(cobblestone, n_recipes, 6)
    pullIntoInventory(quartz, n_recipes, 2)
    pullIntoInventory(quartz, n_recipes, 5)
    turtle.craft()
    pullIntoInventory(quartz, n_recipes * 2, 2)
    turtle.craft()
    while turtle.getItemDetail(1) do
        for i = 1, 2 do
            barrels[i].pullItems(local_name, 1, n_recipes)
        end
        os.sleep(1)
    end

    local n_gold_blocks = math.floor(math.min(count(gold_nuggets) / 81, 7))
    for _, i in pairs({1, 2, 3, 5, 6, 7, 9, 10, 11}) do
        pullIntoInventory(gold_nuggets, n_gold_blocks * 9, i)
    end
    turtle.craft()
    for _, i in pairs({2, 3, 5, 6, 7, 9, 10, 11}) do
        turtle.transferTo(i, n_gold_blocks)
    end
    turtle.craft()
    while turtle.getItemDetail(1) do
        chest.pullItems(local_name, 1)
        os.sleep(1)
    end
end

-- Drop everything from before restart, except chunk vial.
for slot = 1, 15 do
    turtle.select(slot)
    turtle.dropDown()
end

while true do
    local is_online = not redstone.getInput("top")
    local chunk_vial_equipped = turtle.getEquippedLeft() ~= nil
    if is_online ~= chunk_vial_equipped then
        turtle.select(16)
        turtle.equipLeft()
    end
    if is_online then
        craftingStep()
    end
    os.sleep(1)
end
