local async = require "async"
local common = require "common"
local ui = require "ui"
local util = require "util"

local function init()
    -- We can occasionally be in a state where not all peripherals are present. This occurs a) if
    -- the server shuts down/the chunk is unloaded while we're refueling, b) after initial boot.
    -- Let's simplify recovery and setup as much as we can.

    -- Populate lazily to reduce startup cost on normal loads, as the turtle restarts each time it's
    -- placed.
    local slot_by_type = nil
    local function findSlot(item_type)
        if slot_by_type == nil then
            slot_by_type = {}
            async.parMap(util.iota(16), function(slot)
                local item = turtle.getItemDetail(slot)
                -- Why `item.count == 1`? If we've consumed a lava bucket and have an empty bucket,
                -- we should refill that specific bucket rather than a stack of bucket lying around:
                -- there might not even be enough space for a new lava bucket otherwise.
                if item and item.count == 1 then
                    slot_by_type[item.name] = slot
                end
            end)
        end
        return slot_by_type[item_type]
    end

    local p = {}

    for _, upgrade in pairs({
        { name = "sword", side = "left", item = "minecraft:diamond_sword" },
        { name = "hub", side = "right", item = "peripheralworks:netherite_peripheralium_hub" },
    }) do
        local current
        if upgrade.side == "left" then
            current = turtle.getEquippedLeft()
        else
            current = turtle.getEquippedRight()
        end
        if not current then
            local slot = findSlot(upgrade.item)
            assert(slot ~= nil, upgrade.item .. " not found")
            turtle.select(slot)
            if upgrade.side == "left" then
                turtle.equipLeft()
            else
                turtle.equipRight()
            end
        end
        p[upgrade.name] = peripheral.wrap(upgrade.side)
    end

    -- Peripheralium hub seems to guarantee consistent IDs.
    local present_upgrades = {}
    for _, name in pairs(p.hub.getUpgrades()) do
        present_upgrades[name] = true
    end
    for _, upgrade in pairs({
        {
            name = "overworld_end_automata",
            item = "turtlematic:end_automata_core",
            upgrade = "turtlematic:end_automata",
            id = "endAutomata_1",
        },
        {
            name = "nether_end_automata",
            item = "turtlematic:netherite_end_automata_core",
            upgrade = "turtlematic:netherite_end_automata",
            id = "endAutomata_2",
        },
        {
            name = "ender_modem",
            item = "computercraft:wireless_modem_advanced",
            upgrade = "computercraft:wireless_modem_advanced",
            id = "modem_1",
        },
        {
            name = "speaker",
            item = "computercraft:speaker",
            upgrade = "computercraft:speaker",
            id = "speaker_1",
        },
        {
            name = "mimic",
            item = "turtlematic:mimic_gadget",
            upgrade = "turtlematic:mimic",
            id = "mimic_1",
        },
        {
            name = "lava_bucket",
            item = "minecraft:lava_bucket",
            upgrade = "turtlematic:lava_bucket",
            id = nil,
        }
    }) do
        if not present_upgrades[upgrade.upgrade] then
            local slot = findSlot(upgrade.item)
            if not slot and upgrade.name == "lava_bucket" then
                -- Special case: try to fill an empty bucket. This succeeds in the overworld and
                -- fails in the nether, but that seems fine.
                slot = findSlot("minecraft:bucket")
                if slot ~= nil then
                    local down = turtle.inspectDown()
                    assert(not (down and down.name == "minecraft:fire"), "stuck in the nether")
                    turtle.select(slot)
                    turtle.placeUp()
                    while turtle.getItemDetail(slot).name ~= "minecraft:lava_bucket" do
                        turtle.placeUp()
                    end
                end
            end
            assert(slot ~= nil, upgrade.item .. " not found")
            p.hub.equip(slot)
        end
        if upgrade.id ~= nil then
            local wrapped = peripheral.wrap(upgrade.id)
            assert(wrapped, upgrade.item .. " not found")
            p[upgrade.name] = wrapped
        end
    end

    return p
end

local p = init()

os.setComputerLabel("Ender Storage")

local function setMimic()
    p.mimic.setMimic({ block = "spectrum:amethyst_storage_block" })
    p.mimic.setTransformation("t(0.125,0.125,0.125);s(0.75,0.75,0.75)")
end
setMimic()

local function getRefuelAmount()
    return math.floor((turtle.getFuelLimit() - turtle.getFuelLevel()) / 1000)
end

local function refuelInOverworld()
    local n = getRefuelAmount()
    if n == 0 then
        return
    end

    -- Slot 16 should always be empty after depositing. Panicking here would be bad, so don't
    -- assert. Ask for detail to make sure we run on the main thread, since otherwise there doesn't
    -- seem to be any synchronization.
    if turtle.getItemDetail(16, true) then
        return "Storage full??"
    end

    -- Lava buckets are valid peripherals, so we store the bucket in the peripheralium hub.
    -- `unequip` always populates the first available slot, so we have to free up the first slot
    -- since we don't know which one it'll choose otherwise.
    turtle.select(1)
    turtle.transferTo(16)
    p.hub.unequip("turtlematic:lava_bucket")

    for _ = 1, n do
        turtle.refuel()
        turtle.placeUp()
        while turtle.getItemDetail(1).name ~= "minecraft:lava_bucket" do
            turtle.placeUp()
        end
    end

    p.hub.equip(1)
    turtle.select(16)
    turtle.transferTo(1)
end

-- Set up before listening to events.
local function setup()
    -- Calling any warping APIs immediately binds the end automata to the current dimension if it's
    -- not already bound. Assume the first setup runs in the overworld, but otherwise don't make any
    -- assumptions.
    local ok, result = pcall(p.overworld_end_automata.points)
    if ok then
        if not next(result) then
            print("Setting up overworld")
            refuelInOverworld()
            p.overworld_end_automata.savePoint("home")
        end
        return "overworld"
    end

    -- We're not in the overworld, so probably in the nether.
    ok, result = pcall(p.nether_end_automata.points)
    if ok then
        if not next(result) then
            print("Setting up the nether")
            p.nether_end_automata.savePoint("home")
        end
        return "nether"
    end

    error("Storage is not accessible from this dimension.")
end

local current_dimension = setup()

rednet.open(peripheral.getName(p.ender_modem))

local term_width, term_height = term.getSize()

local error_message = nil

local awaited_pong = nil
local inventory_adjusted = async.newNotifyWaiters()
local inventory_adjusted_message = nil

local function adjustInventoryWired(wired_name, goal_inventory)
    -- The previous operation might have timed out, so we need to send a ping and wait for a pong to
    -- ensure the messages are processed up until that point. Wasting a bit of time here is not
    -- a big deal due to the warp cooldown anyway.
    local ping_id = math.random(1, 2147483647)
    awaited_pong = {
        id = ping_id,
        received = async.newNotifyOne(),
        server_id = nil,
    }
    rednet.broadcast({ type = "ping", id = ping_id }, "purple_storage")
    awaited_pong.received.wait()
    local server_id = awaited_pong.server_id

    local needs_retry = true
    while needs_retry do
        rednet.send(server_id, {
            type = "adjust_inventory",
            client = wired_name,
            current_inventory = common.loadInventory(),
            goal_inventory = goal_inventory,
            preview = false,
        }, "purple_storage")
        inventory_adjusted.wait()
        needs_retry = inventory_adjusted_message.needs_retry
    end
end

local has_items_in_inventory = false
local items_to_withdraw = {}

local function countReservedStacks(except_item)
    local count = 0
    for _, item in pairs(items_to_withdraw) do
        if item ~= except_item then
            count = count + math.ceil(item.count / item.maxCount)
        end
    end
    return count
end

local function renderListUi()
    term.setBackgroundColor(colors.black)
    term.clear()

    local highlighted_keys = {}
    local first_y = term_height - #items_to_withdraw
    for i, item in ipairs(items_to_withdraw) do
        highlighted_keys[util.getItemKey(item)] = true
        local y = first_y + i - 1
        term.setCursorPos(8, y)
        term.setBackgroundColor(colors.black)
        common.writeFormattedText(common.formatItemName(item), colors.green)
        term.setCursorPos(1, y)
        term.setBackgroundColor(colors.green)
        term.setTextColor(colors.white)
        local count = string.format("%6s", common.formatItemCount(item))
        local pos_s = count:find("s")
        if pos_s == nil then
            term.write(count)
        else
            term.write(count:sub(1, pos_s - 1))
            term.setTextColor(colors.lime)
            term.write("s")
            term.setTextColor(colors.white)
            term.write(count:sub(pos_s + 1))
        end
    end

    common.renderIndex(2, term_height - 1 - #items_to_withdraw, highlighted_keys)

    if error_message ~= nil then
        term.setCursorPos(1, term_height)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.red)
        term.clearLine()
        term.write(error_message)
    elseif next(items_to_withdraw) then
        term.setCursorPos(8, term_height)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.green)
        term.clearLine()
        if has_items_in_inventory then
            term.write("Click to deposit and withdraw")
        else
            term.write("Click here to withdraw")
        end
        term.setCursorPos(1, term_height)
        term.setBackgroundColor(colors.red)
        term.write("Cancel")
    elseif has_items_in_inventory then
        term.setCursorPos(1, term_height)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.green)
        term.clearLine()
        term.write("Click here to deposit")
    else
        term.setCursorPos(1, term_height)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.gray)
        term.clearLine()
        term.write("Deposit items or click to withdraw")
    end

    common.renderSearchBar()
end

local edited_item = nil -- either the same object as in `items_to_withdraw` or unique if absent
local count_field = ui.TextField:new()

local function renderItemUi()
    term.setBackgroundColor(colors.black)
    term.clear()

    term.setTextColor(colors.white)
    term.setCursorPos(8, 3)
    term.write(common.formatItemName(edited_item))

    term.setTextColor(colors.lightGray)
    term.setCursorPos(8, 5)
    term.write("How many to pull?")
    term.setCursorPos(8, 6)
    term.write("Either ")
    term.setTextColor(colors.green)
    term.write("Ns M")
    term.setTextColor(colors.lightGray)
    term.write(" or formula")
    term.setCursorPos(8, 7)
    term.write("Leave empty to remove.")

    local server_item = common.index[util.getItemKey(edited_item)]
    local server_count = 0
    if server_item then
        server_count = server_item.count
    end
    term.setCursorPos(8, 10)
    term.setTextColor(colors.white)
    term.write(string.format("In storage: %d", server_count))

    if error_message ~= nil then
        term.setCursorPos(8, 12)
        term.setTextColor(colors.red)
        term.write(error_message)
    end

    term.setCursorPos(8, 8)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(count_field.value .. (" "):rep(term_width - 14 - #count_field.value))
    term.setCursorPos(7 + count_field.position, 8)
    term.setCursorBlink(true)
end

local function parseCount(s, stack_size)
    s = s:match("^%s*(.-)%s*$") -- trim
    if s == "" then
        return true, 0
    end

    local stacks, items = s:match("^(%d+)s%s*(%d+)$")
    if stacks ~= nil then
        return true, stacks * stack_size + items
    end

    stacks = s:match("^(%d+)s$")
    if stacks ~= nil then
        return true, stacks * stack_size
    end

    local f, err = load("return " .. s, "")
    if f == nil then
        return false, err:match("^.-:.-: (.+)$") or err
    end

    local ok, result = pcall(f)
    if not ok then
        return false, result:match("^.-:.-: (.+)$") or result
    end

    if type(result) ~= "number" then
        return false, "Not a number"
    end

    -- The weird `not` construct checks for NaN.
    if not (result >= 0) or result % 1 ~= 0 then
        return false, "Invalid number"
    end

    return true, result
end

local function renderScreen()
    if edited_item == nil then
        renderListUi()
    else
        renderItemUi()
    end
end

local function onItemEnter()
    local ok, result = parseCount(count_field.value, edited_item.maxCount)
    if ok then
        local server_item = common.index[util.getItemKey(edited_item)]
        local server_count = 0
        if server_item then
            server_count = server_item.count
        end
        if result > server_count then
            ok = false
            result = "Fewer items in storage"
        elseif math.ceil(result / edited_item.maxCount) + countReservedStacks(edited_item) > 15 then
            ok = false
            result = "Can't fit in inventory"
        end
    end
    if not ok then
        error_message = result
        renderScreen()
        return
    end

    edited_item.count = result

    local index = util.findInTable(items_to_withdraw, edited_item)
    if index == nil then
        if result > 0 then
            table.insert(items_to_withdraw, edited_item)
        end
    else
        if result == 0 then
            table.remove(items_to_withdraw, index)
        end
    end

    edited_item = nil

    renderScreen()
end

local function openItemDialog(item)
    local key = util.getItemKey(item)
    edited_item = nil
    for _, reserved_item in pairs(items_to_withdraw) do
        if util.getItemKey(reserved_item) == key then
            edited_item = reserved_item
            break
        end
    end
    if edited_item == nil then
        if countReservedStacks() == 15 then
            -- Doesn't make sense to open non-reserved items if we don't have space for them.
            error_message = "All slots reserved"
            renderScreen()
            return
        end
        edited_item = util.itemWithCount(item, 0)
        count_field:clear()
    else
        count_field.value = common.formatItemCount(edited_item)
        count_field.position = #count_field.value + 1
    end

    renderScreen()
end

local function onInteraction()
    if error_message ~= nil then
        error_message = nil
        renderScreen()
    end
end

local function getEndAutomata()
    return p[current_dimension .. "_end_automata"]
end

local function warp(point_name)
    local automata = getEndAutomata()
    while true do
        local ok, err = automata.warpToPoint(point_name)
        if ok then
            return true
        end
        if err == "warp is on cooldown" then
            os.sleep(automata.getCooldown("warp") / 1000)
        elseif err == "Move forbidden" then
            -- the chunk is unloaded
            return false
        else
            error(err)
        end
    end
end

local function connectToWiredModem()
    local wired_modem = nil
    while not wired_modem do
        os.sleep(0.1)
        wired_modem = peripheral.find("modem", function(_, modem)
            return not modem.isWireless()
        end)
    end
    local wired_name = wired_modem.getNameLocal()
    assert(wired_name, "modem disconnected from network")
    return wired_name
end

local function adjustInventoryOverworld(wired_name, goal_inventory)
    -- The server might be dead, disconnected, or there might be lag. Either way, we can't just sit
    -- here forever, since the player might move around and forget where they left the client, so
    -- we just timeout and come back. If the server eventually wakes up and tries to interact with
    -- the client, we'll already have left the wired network by that point, so it'll fail silently;
    -- or if we return back by that point, we'll quickly sort it out by ping-pong.
    local key = async.race({
        sleep = util.bind(os.sleep, 5),
        adjust = util.bind(adjustInventoryWired, wired_name, goal_inventory),
    })
    if key == "sleep" then
        return "Operation timed out"
    end
    -- We only refuel if we've successfully interacted with the server, since otherwise we might
    -- race and the server will take our lava bucket away, which would be disastrous. We'd love to
    -- refuel unconditionally, since otherwise we can run out of fuel, but that probably won't end
    -- up mattering: an advanced turtle filled to the brim can do 500 round trips over a 10k
    -- distance.
    return refuelInOverworld()
end

local waiting_on_order = nil

local function adjustInventoryNether(wired_name, goal_inventory)
    local rail, cart = common.wrapRailWired("bottom")

    -- Before we mutate anything, sanity checks don't need to panic.
    if not cart then
        return "No minecart"
    end

    async.parMap(util.iota(16), function(slot)
        rail.pullItems(wired_name, slot, nil, slot)
    end)

    -- Unlike the overworld, the helper can always refill our bucket, because the server operates
    -- directly on the cart, so we're free to drink it now if necessary. We can only request
    -- a single bucket of lava to be refilled, but it's sufficient for a 250k long roundtrip,
    -- which should be plenty.
    local need_refuel = getRefuelAmount() > 0
    if need_refuel then
        -- All slots are empty, so this should populate slot 1.
        p.hub.unequip("turtlematic:lava_bucket")
        turtle.select(1)
        turtle.refuel()
        rail.pullItems(wired_name, 1, nil, 27)
    end

    -- Place an order, using the cart's UUID as a unique key. The cart retains its UUID when it
    -- passes through the portal, so this is a major simplification.
    waiting_on_order = {
        cart = cart.uuid,
        delivered = async.newNotifyOne(),
    }
    rednet.broadcast({
        type = "place_order",
        cart = cart.uuid,
        goal_inventory = goal_inventory,
    }, "purple_storage")

    -- Pushing the cart gives it high velocity even on unpowered rails.
    common.sendCartToPortal(rail)

    -- We're now waiting on the helper. There isn't much we can overlap: we already have a sword in
    -- our hand, and the cart is under us, so we don't need to turn to attack it.
    --
    -- There is no timeout logic here: if we tried to warp away on time out, the cart would at some
    -- point arrive in non-empty state, which we don't know how to deal with. Since the helper is
    -- much simpler than the storage server, there should be fewer odd failure modes that necessiate
    -- timing out; and a client can only break its own helper if things go south, so other clients
    -- should stay operational.
    waiting_on_order.delivered.wait()

    -- The cart should appear soon, so busy waiting is fine.
    while rail.size() == 0 do
        os.sleep(0.1)
    end

    -- If adjustment failed due to timeout, the cart can contain both an item in slot 16 and
    -- a refilled lava bucket. Take out the latter first, since otherwise we might not have space.
    if need_refuel then
        rail.pushItems(wired_name, 27, nil, 1)
        p.hub.equip(1)
    end

    local is_ok = waiting_on_order.response.error_message == nil

    if not is_ok then
        -- Resetting cooldown requires an empty slot and for the minecart to be empty, but we might
        -- not have enough space for that if adjustment didn't complete, so wait for the cooldown to
        -- end naturally. We should probably move this sleep to the start of the next operation, but
        -- this only occurs on failures and should be rare if the storage is always online.
        os.sleep(15)
    end

    async.parMap(util.iota(16), function(slot)
        rail.pushItems(wired_name, slot, nil, slot)
    end)

    if is_ok then
        -- We're guaranteed to have a free 16th slot on successful adjustment.
        turtle.select(16)
        turtle.attackDown()
        turtle.placeDown()
    end

    return waiting_on_order.response.error_message
end

local committing = false

local function commitOperation()
    if committing then
        -- If the user interacts with the turtle while it's teleporting away, ignore that.
        -- Reentering would be disasterous.
        return
    end
    committing = true

    local goal_inventory = {}
    local next_slot = 1
    for _, item in ipairs(items_to_withdraw) do
        local count = item.count
        while count > 0 do
            local cur_count = math.min(count, item.maxCount)
            count = count - cur_count
            goal_inventory[next_slot] = util.itemWithCount(item, cur_count)
            next_slot = next_slot + 1
        end
    end

    local automata = getEndAutomata()

    assert(automata.savePoint("outskirts"), "failed to save point")

    p.speaker.playSound("entity.enderman.teleport")
    if not warp("home") then
        error_message = "Storage unloaded"
    else
        local wired_name = connectToWiredModem()
        if current_dimension == "overworld" then
            error_message = adjustInventoryOverworld(wired_name, goal_inventory)
        else
            error_message = adjustInventoryNether(wired_name, goal_inventory)
        end

        if error_message == nil then
            items_to_withdraw = {}
        end

        if warp("outskirts") then
            p.speaker.playSound("entity.enderman.teleport")
        else
            error_message = "Outskirts unloaded"
        end
    end

    committing = false
    renderScreen()
end

async.subscribe("key", function(key_code)
    onInteraction()
    if ui.ctrl_pressed and key_code == keys.c then -- cancel
        if edited_item == nil then
            items_to_withdraw = {}
        else
            edited_item = nil
        end
        renderScreen()
    elseif key_code == keys.enter then
        if edited_item ~= nil then
            onItemEnter()
        end
    else
        if edited_item == nil then
            if common.onKey(key_code, term_height - 2 - #items_to_withdraw) ~= nil then
                renderScreen()
            end
        else
            if count_field:onKey(key_code) then
                renderScreen()
            end
        end
    end
end)
async.subscribe("char", function(ch)
    onInteraction()
    if edited_item == nil then
        if common.onChar(ch) ~= nil then
            renderScreen()
        end
    else
        if count_field:onChar(ch) then
            renderScreen()
        end
    end
end)
async.subscribe("mouse_click", function(button, x, y)
    onInteraction()
    if edited_item ~= nil then
        return
    end
    if button ~= 1 then
        return
    end
    local first_y = term_height - #items_to_withdraw
    if y >= 2 and y < first_y then
        local item = common.getVisibleItem(y - 1)
        if item then
            openItemDialog(item)
        end
    elseif y >= first_y and y < term_height then
        openItemDialog(items_to_withdraw[y - first_y + 1])
    elseif y == term_height then
        if next(items_to_withdraw) then
            if x <= 7 then
                items_to_withdraw = {}
                renderScreen()
            else
                commitOperation()
            end
        elseif has_items_in_inventory then
            commitOperation()
        end
    end
end)
async.subscribe("mouse_scroll", function(direction)
    onInteraction()
    if edited_item == nil then
        common.onMouseScroll(direction)
        renderScreen()
    end
end)

local turtle_inventory = async.newNotifyOne()
async.subscribe("turtle_inventory", turtle_inventory.notifyOne)
async.spawn(function()
    while true do
        local old_has_items_in_inventory = has_items_in_inventory
        has_items_in_inventory = next(common.loadInventory()) ~= nil
        if has_items_in_inventory ~= old_has_items_in_inventory then
            renderScreen()
        end
        turtle_inventory.wait()
    end
end)

async.spawn(function()
    while true do
        local computer_id, msg = rednet.receive("purple_storage")
        if msg.type == "inventory_adjusted" then
            -- `notifyWaiters` guarantees that a delayed response (occurring for whatever reason)
            -- doesn't store a permit that can be interpreted as an immediate response later.
            inventory_adjusted_message = msg
            inventory_adjusted.notifyWaiters()
        elseif msg.type == "patch_index" then
            common.patchIndex(msg)

            -- If the counts of some items were reduced, we might be unable to satisfy the request.
            -- Make this obvious to the user.
            local remaining_items = {}
            for _, item in ipairs(items_to_withdraw) do
                local key = util.getItemKey(item)
                local server_item = common.index[key]
                if server_item then
                    item.count = math.min(item.count, server_item.count)
                    if item.count > 0 then
                        table.insert(remaining_items, item)
                    end
                end
            end
            items_to_withdraw = remaining_items

            renderScreen()
        elseif msg.type == "pong" then
            if awaited_pong and msg.id == awaited_pong.id then
                awaited_pong.server_id = computer_id
                awaited_pong.received.notifyOne()
            end
        elseif msg.type == "order_delivered" then
            if waiting_on_order and msg.cart == waiting_on_order.cart then
                waiting_on_order.response = msg
                waiting_on_order.delivered.notifyOne()
            end
        end
    end
end)

rednet.broadcast({ type = "request_index" }, "purple_storage")

async.drive()
