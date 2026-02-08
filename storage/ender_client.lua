local async = require "async"
local common = require "common"
local ui = require "ui"
local util = require "util"

local function init()
    -- We can occasionally be in a state where not all peripherals are present. This occurs a) if the
    -- server shuts down/the chunk is unloaded while we're refueling, b) after initial boot. Let's
    -- simplify recovery and setup.

    -- Populate lazily to reduce startup cost on normal loads.
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
        -- vanutp's patch for rendering mimicked blocks in item models doesn't scan hub internals
        -- and only works reliably with the left slot.
        { name = "mimic", side = "left", item = "turtlematic:mimic_gadget" },
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
            name = "end_automata",
            item = "turtlematic:end_automata_core",
            upgrade = "turtlematic:end_automata",
            id = "endAutomata_1",
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
            name = "lava_bucket",
            item = "minecraft:lava_bucket",
            upgrade = "turtlematic:lava_bucket",
            id = "lava_bucket_1",
        }
    }) do
        if not present_upgrades[upgrade.upgrade] then
            local slot = findSlot(upgrade.item)
            if not slot and upgrade.name == "lava_bucket" then
                -- Special case: try to fill an empty bucket.
                slot = findSlot("minecraft:bucket")
                if slot ~= nil then
                    turtle.select(slot)
                    turtle.placeDown()
                    while turtle.getItemDetail(slot).name ~= "minecraft:lava_bucket" do
                        turtle.placeDown()
                    end
                end
            end
            assert(slot ~= nil, upgrade.item .. " not found")
            p.hub.equip(slot)
        end
        local wrapped = peripheral.wrap(upgrade.id)
        assert(wrapped, upgrade.item .. " not found")
        p[upgrade.name] = wrapped
    end

    return p
end

local p = init()

local function refuel()
    local n = math.floor((turtle.getFuelLimit() - turtle.getFuelLevel()) / 1000)
    if n == 0 then
        return
    end

    -- Slot 16 should always be empty after depositing. Panicking here would be bad, so don't
    -- assert. Ask for detail to make sure we run on the main thread, since otherwise there doesn't
    -- seem to be any synchronization.
    if turtle.getItemDetail(16, true) then
        error_message = "Storage full??"
        return
    end

    turtle.select(1)
    turtle.transferTo(16)

    -- Lava buckets are valid peripherals, so we can store a bucket within the peripheralium hub.
    -- `unequip` always populates the first available slot, which is guaranteed to be 1.
    p.hub.unequip("turtlematic:lava_bucket")

    for _ = 1, n do
        turtle.refuel()
        turtle.placeDown()
        while turtle.getItemDetail(1).name ~= "minecraft:lava_bucket" do
            turtle.placeDown()
        end
    end

    p.hub.equip(1)

    turtle.select(16)
    turtle.transferTo(1)
end

-- Set up before listening to events.
if not next(p.end_automata.points()) then
    print("Setting up")
    refuel()
    p.end_automata.savePoint("home")
end

rednet.open(peripheral.getName(p.ender_modem))
os.setComputerLabel("Ender Storage")
p.mimic.setMimic({ block = "spectrum:amethyst_storage_block" })
p.mimic.setTransformation("t(0.125,0.125,0.125);s(0.75,0.75,0.75)")

local term_width, term_height = term.getSize()

local error_message = nil

local awaited_pong = nil
local inventory_adjusted = async.newNotifyWaiters()
local inventory_adjusted_message = nil

local function adjustInventory(wired_name, goal_inventory)
    -- The previous operation might have timed out, so we need to send a ping and wait for a pong to
    -- ensure the messages are processed up until that point. Wasting a bit of time here is not
    -- a big deal due to the warp cooldown anyway.
    local ping_id = math.random(1, 2147483647)
    awaited_pong = {
        id = ping_id,
        received = async.newNotifyOne(),
        server_id = nil,
    }
    rednet.send(rednet.CHANNEL_BROADCAST, { type = "ping", id = ping_id }, "purple_storage")
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
    s = s:match("^%s*(.-)%s*$")
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

local function warp(point_name)
    while true do
        local ok, err = p.end_automata.warpToPoint(point_name)
        if ok then
            return
        end
        if err ~= "warp is on cooldown" then
            error(err)
        end
        os.sleep(p.end_automata.getCooldown("warp") / 1000)
    end
end

local committing = false

local function commitOperation()
    assert(not committing, "cannot commit while committing")
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

    assert(p.end_automata.savePoint("outskirts"), "failed to save point")

    p.speaker.playSound("entity.enderman.teleport")
    warp("home")

    local wired_modem = nil
    while not wired_modem do
        os.sleep(0.1)
        wired_modem = peripheral.find("modem", function(_, modem)
            return not modem.isWireless()
        end)
    end
    local wired_name = wired_modem.getNameLocal()
    assert(wired_name, "modem disconnected from network")

    -- The server might be dead, disconnected, or there might be lag. Either way, we can't just sit
    -- here forever, since the player might move around and forget where they left the client, so
    -- we just timeout and come back. If the server eventually wakes up and tries to interact with
    -- the client, we'll already have left the wired network by that point, so it'll fail silently;
    -- or if we return back by that point, we'll quickly sort it out by ping-pong.
    local key = async.race({
        sleep = util.bind(os.sleep, 5),
        adjust = util.bind(adjustInventory, wired_name, goal_inventory),
    })
    if key == "sleep" then
        error_message = "Operation timed out"
    else
        items_to_withdraw = {}
        -- We only refuel if we've successfully interacted with the server, since otherwise we might
        -- race and the server will take our lava bucket away, which would be disastrous. We'd love
        -- to refuel unconditionally, since otherwise we can run out of fuel, but that probably
        -- won't end up mattering: an advanced turtle filled to the brim can do 500 round trips over
        -- a 10k distance.
        refuel()
    end

    warp("outskirts")
    p.speaker.playSound("entity.enderman.teleport")

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
        openItemDialog(common.getVisibleItem(y - 1))
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
        end
    end
end)

rednet.send(rednet.CHANNEL_BROADCAST, { type = "request_index" }, "purple_storage")

async.drive()
