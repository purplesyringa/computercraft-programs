local async = require "async"
local common = require "common"
local util = require "util"

local modem = peripheral.find("modem")
assert(modem, "Modem not available")
rednet.open(peripheral.getName(modem))

local mimic = peripheral.find("mimic")
if mimic then
    pcall(mimic.setMimic, { block = "spectrum:block/onyx_storage_block" })
end

os.setComputerLabel("Storage")

local _, term_height = term.getSize()

-- Detect accidental modem disconnects.
local modem_connected = async.newNotifyWaiters()
local wired_name = nil -- will be initialized later

local server_id = rednet.CHANNEL_BROADCAST

-- The state of the inventory we're trying to achieve.
local goal_inventory = {}
-- If `nil`, we're in preview mode. Otherwise, the item we're trying to pull into all slots.
local selected_item = nil
local readjust = async.newNotifyOne()

local function renderScreen()
    term.setBackgroundColor(colors.black)
    term.clear()

    local highlighted_keys = {
        [util.getItemKey(selected_item)] = true
    }
    common.renderIndex(2, term_height - 1, highlighted_keys)

    if wired_name == nil then
        term.setCursorPos(1, term_height)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.red)
        term.clearLine()
        term.write("Modem disconnected")
    elseif selected_item then
        term.setCursorPos(8, term_height)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.green)
        term.clearLine()
        term.write(string.format("Pulling %s", common.formatItemName(selected_item)))
        term.setCursorPos(1, term_height)
        term.setBackgroundColor(colors.red)
        term.write("Cancel")
    else
        term.setCursorPos(1, term_height)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.gray)
        term.clearLine()
        term.write("Click row to pull completely")
    end

    common.renderSearchBar()
end

local function setPreviewGoal(is_synchronous_update)
    selected_item = nil

    if not common.hasSearchQuery() then
        goal_inventory = {}
        return
    end

    -- We don't want to rearrange existing items/slots in the inventory on index updates, since that
    -- can race with the user taking out items.
    if is_synchronous_update then
        goal_inventory = {}
    end

    local present_in_goal = {}
    for _, item in pairs(goal_inventory) do
        present_in_goal[util.getItemKey(item)] = true
    end

    local j = 1
    -- Fill slots from 1 to 15, but leave slot 16 empty for depositing.
    for i = 1, 15 do
        if not goal_inventory[i] then
            local item = common.filtered_index[j]
            while item and present_in_goal[util.getItemKey(item)] do
                j = j + 1
                item = common.filtered_index[j]
            end
            if item then
                goal_inventory[i] = util.itemWithCount(item, item.maxCount)
                j = j + 1
            end
        end
    end
end

local interaction_timer = nil
local function recordInteraction()
    if interaction_timer ~= nil then
        os.cancelTimer(interaction_timer)
    end
    interaction_timer = os.startTimer(10)
end
async.subscribe("timer", function(id)
    if id == interaction_timer and (common.hasSearchQuery() or selected_item) then
        -- Assume the user has stopped interacting with the client.
        common.reset()
        setPreviewGoal(true)
        readjust.notifyOne()
        renderScreen()
    end
end)

async.subscribe("key", function(key_code)
    recordInteraction()
    if common.ctrl_pressed and key_code == keys.c then -- cancel pulling
        if selected_item then
            setPreviewGoal(true)
            readjust.notifyOne()
            renderScreen()
        end
    else
        local changes = common.onKey(key_code, term_height - 2)
        if changes == "search" then
            setPreviewGoal(true)
            readjust.notifyOne()
        end
        if changes ~= nil then
            renderScreen()
        end
    end
end)
async.subscribe("key_up", recordInteraction)
async.subscribe("char", function(ch)
    recordInteraction()
    if common.onChar(ch) == "search" then
        setPreviewGoal(true)
        readjust.notifyOne()
        renderScreen()
    end
end)
async.subscribe("mouse_click", function(button, _, y)
    recordInteraction()
    local updated = false
    if button == 1 and y > 1 and y < term_height then
        local item = common.getVisibleItem(y - 1)
        if item and util.getItemKey(item) ~= util.getItemKey(selected_item) then
            for slot = 1, 15 do
                goal_inventory[slot] = util.itemWithCount(item, item.maxCount)
            end
            selected_item = item
            updated = true
        end
    end
    if not updated and selected_item then
        setPreviewGoal(true)
        updated = true
    end
    if updated then
        readjust.notifyOne()
        renderScreen()
    end
end)
async.subscribe("mouse_scroll", function(direction)
    recordInteraction()
    common.onMouseScroll(direction)
    renderScreen()
end)

local awaited_pong = nil
local inventory_adjusted = async.newNotifyWaiters()
async.subscribe("turtle_inventory", readjust.notifyOne)
async.spawn(function()
    turtle.select(16)
    while true do
        local current_inventory = nil
        if wired_name ~= nil then
            current_inventory = common.loadInventory()
        end
        -- Handle TOCTOU where the modem is disconnected while `loadInventory` is underway.
        while wired_name == nil do
            modem_connected.wait()
            current_inventory = common.loadInventory()
        end

        rednet.send(server_id, {
            type = "adjust_inventory",
            client = wired_name,
            current_inventory = current_inventory,
            goal_inventory = goal_inventory,
            preview = selected_item == nil,
        }, "purple_storage")
        -- If we're disconnected from the wired network, but the modems are still wired, we'll
        -- receive a message, but our inventory may fail to update, possibly partially. We'll
        -- trigger readjustment when we're connected back, but for now this is everything we can do.
        local key = async.race({
            sleep = util.bind(os.sleep, 1),
            response = inventory_adjusted.wait,
        })
        if key == "sleep" then
            -- Server died, was disconnected, or there's lag; either way, wait for the request to
            -- complete before following up. Also trigger readjustment immediately, since we might
            -- have lost index notifications.
            local ping_id = math.random(1, 2147483647)
            awaited_pong = {
                id = ping_id,
                received = async.newNotifyOne(),
            }
            local send_task = async.spawn(function()
                while true do
                    rednet.send(server_id, { type = "ping", id = ping_id }, "purple_storage")
                    os.sleep(1)
                end
            end)
            awaited_pong.received.wait()
            send_task.cancel()
        else
            readjust.wait()
        end
        recordInteraction()
    end
end)

async.spawn(function()
    while true do
        local computer_id, msg = rednet.receive("purple_storage")
        if msg.type == "inventory_adjusted" then
            server_id = computer_id
            -- `notifyWaiters` guarantees that a delayed response (occurring for whatever reason)
            -- doesn't store a permit that can be interpreted as an immediate response later.
            inventory_adjusted.notifyWaiters()
        elseif msg.type == "request_inventory" then
            server_id = computer_id
            readjust.notifyOne()
        elseif msg.type == "patch_index" then
            server_id = computer_id
            common.patchIndex(msg)
            -- The server sends `fullness` updates after every operation, even if it didn't touch
            -- any items -- make sure this doesn't cause an infinite loop.
            if next(msg.items) then
                if selected_item == nil then
                    setPreviewGoal(false)
                end
                -- Force readjustment regardless of whether the goal inventory was changed, since
                -- the available count might have changed for already existing items.
                readjust.notifyOne()
            end
            renderScreen()
        elseif msg.type == "peripherals_changed" then
            server_id = computer_id
            local was_connected = wired_name ~= nil
            wired_name = modem.getNameLocal()
            local is_connected = wired_name ~= nil
            if is_connected and not was_connected then
                modem_connected.notifyWaiters()
            end
            if is_connected ~= was_connected then
                renderScreen()
            end
            -- Schedule readjustment regardless of whether we recognized any changes, since they
            -- could happen so quickly that they are undetectable.
            readjust.notifyOne()
        elseif msg.type == "pong" then
            server_id = computer_id
            if awaited_pong and msg.id == awaited_pong.id then
                awaited_pong.received.notifyOne()
            end
        end
    end
end)

rednet.send(server_id, { type = "request_index" }, "purple_storage")

-- Check modem status only after we subscribe to rednet, since otherwise we could miss
-- a notification.
wired_name = modem.getNameLocal()
if wired_name ~= nil then
    modem_connected.notifyWaiters()
end

async.drive()
