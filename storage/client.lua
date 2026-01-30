local async = require "async"
local util = require "util"

local modem = peripheral.find("modem")
assert(modem, "Modem not available")
rednet.open(peripheral.getName(modem))

os.setComputerLabel("Storage")

local term_width, term_height = term.getSize()

-- Detect accidental modem disconnects.
local modem_connected = async.newNotify()
local wired_name = nil -- will be initialized later

local server_id = rednet.CHANNEL_BROADCAST

local search_query = ""
local cursor_pos = 1
local scroll_pos = 1
local index = {} -- Type: { [key] = item, ... }
local fullness = 0 -- percentage
local filtered_index = {} -- Type: { item, ... }, sorted by decreasing count

-- The state of the inventory we're trying to achieve.
local goal_inventory = {}
-- If `nil`, we're in preview mode. Otherwise, the item we're trying to pull into all slots.
local selected_item = nil
local readjust = async.newNotify()

local function formatItemName(item)
    if item.name == "minecraft:enchanted_book" and next(item.enchantments or {}) then
        local enchantments = {}
        for _, enchantment in ipairs(item.enchantments) do
            table.insert(enchantments, enchantment.displayName)
        end
        return table.concat(enchantments, " + ")
    end

    -- Smithing templates don't export their name anywhere. Match by display name because mods add
    -- their own smithing templates without setting any recognizable tags. This assumes English
    -- locale, but that makes some sense because we can't print non-Latin characters anyway.
    if item.displayName == "Smithing Template" then
        local i = item.name:find(":")
        local name = item.name:sub(i + 1):gsub("_smithing_template$", "")
        local words = {}
        for word in name:gmatch("[^_]+") do
            table.insert(words, word:sub(1, 1):upper() .. word:sub(2))
        end
        return table.concat(words, " ")
    end

    return item.displayName
end

local function formatItemCount(item)
    if item.maxCount < 64 or item.count < 320 then
        return string.format("%d", item.count)
    end
    local stacks = math.floor(item.count / item.maxCount)
    local remainder = item.count % item.maxCount
    if remainder == 0 or stacks >= 100 then
        return string.format("%ds", stacks)
    else
        return string.format("%ds %d", stacks, remainder)
    end
end

local function renderScreen()
    scroll_pos = math.max(1, math.min(scroll_pos, #filtered_index - term_height + 3))
    term.setBackgroundColor(colors.black)
    term.clear()

    term.setCursorPos(8, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(search_query)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.yellow)
    term.setTextColor(colors.black)
    term.write(string.format("%5d%%", fullness))

    for y = 2, term_height - 1 do
        local item = filtered_index[scroll_pos + y - 2]
        if item then
            term.setCursorPos(8, y)
            term.setBackgroundColor(colors.black)
            if util.getItemKey(item) == util.getItemKey(selected_item) then
                term.setTextColor(colors.green)
            else
                term.setTextColor(colors.white)
            end
            term.write(formatItemName(item))
        end
        term.setCursorPos(1, y)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        if item then
            local count = string.format("%6s", formatItemCount(item))
            local pos_s = count:find("s")
            if pos_s == nil then
                term.write(count)
            else
                term.write(count:sub(1, pos_s - 1))
                term.setTextColor(colors.lightBlue)
                term.write("s")
                term.setTextColor(colors.white)
                term.write(count:sub(pos_s + 1))
            end
        else
            term.write("      ")
        end
    end

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
        term.write(string.format("Pulling %s", formatItemName(selected_item)))
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

    term.setCursorPos(7 + cursor_pos, 1)
    term.setCursorBlink(true)
    term.setTextColor(colors.white)
end

local function itemMatchesSearch(item)
    if search_query == "" then
        return true
    end

    if search_query:sub(1, 1) == "@" then
        local i = item.name:find(":")
        local mod_name = item.name:sub(1, i - 1)
        local mod_search_query = search_query:sub(2)
        return util.stringContainsCaseInsensitive(mod_name, mod_search_query)
    end

    if search_query:sub(1, 1) == "#" then
        local tag_search_query = search_query:sub(2)
        for tag, _ in pairs(item.tags) do
            if util.stringContainsCaseInsensitive(tag, tag_search_query) then
                return true
            end
        end
        return false
    end

    local function checkNameOrDisplayName(obj)
        return (
            util.stringContainsCaseInsensitive(obj.name, search_query)
            or util.stringContainsCaseInsensitive(obj.displayName, search_query)
        )
    end

    if checkNameOrDisplayName(item) then
        return true
    end
    -- Some items, like smithing templates, are formatted into a name that is not present as
    -- a substring in data. Recognize that.
    if util.stringContainsCaseInsensitive(formatItemName(item), search_query) then
        return true
    end
    for _, lore in pairs(item.lore or {}) do
        if util.stringContainsCaseInsensitive(lore, search_query) then
            return true
        end
    end
    for _, enchantment in pairs(item.enchantments or {}) do
        if checkNameOrDisplayName(enchantment) then
            return true
        end
    end
    for _, effect in pairs(item.potionEffects or {}) do
        if checkNameOrDisplayName(effect) then
            return true
        end
    end
    return false
end

local function updateFilteredIndex()
    filtered_index = {}
    for _, item in pairs(index) do
        if item.count > 0 and itemMatchesSearch(item) then
            table.insert(filtered_index, item)
        end
    end
    table.sort(filtered_index, function(a, b)
        if a.count == b.count then
            return util.getItemKey(a) < util.getItemKey(b)
        end
        return a.count > b.count
    end)
end

local function setPreviewGoal()
    goal_inventory = {}
    if search_query ~= "" then
        -- Fill slots from 1 to 15, but leave slot 16 empty for depositing.
        for i = 1, 15 do
            local item = filtered_index[i]
            if item then
                goal_inventory[i] = util.itemWithCount(item, item.maxCount)
            end
        end
    end
    selected_item = nil
end

local function handleSearchQueryUpdate()
    updateFilteredIndex()
    setPreviewGoal()
    renderScreen()
    readjust.notifyOne()
end

local interaction_timer = nil
local function recordInteraction()
    if interaction_timer ~= nil then
        os.cancelTimer(interaction_timer)
    end
    interaction_timer = os.startTimer(10)
end
async.subscribe("timer", function(id)
    if id == interaction_timer and search_query ~= "" then
        -- Assume the user has stopped interacting with the client.
        search_query = ""
        cursor_pos = 1
        scroll_pos = 1
        handleSearchQueryUpdate()
    end
end)

local ctrl_pressed = false
async.subscribe("key", function(key_code)
    recordInteraction()
    if key_code == keys.backspace or key_code == keys.capsLock then -- capslock for Colemak
        if cursor_pos > 1 then
            if ctrl_pressed then
                search_query = search_query:sub(cursor_pos)
                cursor_pos = 1
            else
                search_query = search_query:sub(1, cursor_pos - 2) .. search_query:sub(cursor_pos)
                cursor_pos = cursor_pos - 1
            end
            handleSearchQueryUpdate()
        end
    elseif key_code == keys.delete then
        if cursor_pos <= #search_query then
            search_query = search_query:sub(1, cursor_pos - 1) .. search_query:sub(cursor_pos + 1)
            handleSearchQueryUpdate()
        end
    elseif ctrl_pressed and key_code == keys["c"] then
        if selected_item then
            selected_item = nil
            setPreviewGoal()
            renderScreen()
            readjust.notifyOne()
        end
    elseif ctrl_pressed and key_code == keys["d"] then
        search_query = ""
        cursor_pos = 1
        handleSearchQueryUpdate()
    elseif key_code == keys.right then
        if cursor_pos <= #search_query then
            cursor_pos = cursor_pos + 1
            renderScreen()
        end
    elseif key_code == keys.left then
        if cursor_pos > 1 then
            cursor_pos = cursor_pos - 1
            renderScreen()
        end
    elseif key_code == keys.up then
        scroll_pos = scroll_pos - 1
        renderScreen()
    elseif key_code == keys.down then
        scroll_pos = scroll_pos + 1
        renderScreen()
    elseif key_code == keys.pageUp then
        scroll_pos = scroll_pos - (term_height - 2)
        renderScreen()
    elseif key_code == keys.pageDown then
        scroll_pos = scroll_pos + (term_height - 2)
        renderScreen()
    elseif key_code == keys.home then
        cursor_pos = 1
        renderScreen()
    elseif key_code == keys["end"] then
        cursor_pos = #search_query + 1
        renderScreen()
    elseif key_code == keys.leftCtrl or key_code == keys.rightCtrl then
        ctrl_pressed = true
    end
end)
async.subscribe("key_up", function(key_code)
    recordInteraction()
    if key_code == keys.leftCtrl or key_code == keys.rightCtrl then
        ctrl_pressed = false
    end
end)
async.subscribe("char", function(ch)
    if not ctrl_pressed then
        search_query = search_query:sub(1, cursor_pos - 1) .. ch .. search_query:sub(cursor_pos)
        cursor_pos = cursor_pos + 1
        handleSearchQueryUpdate()
    end
end)
async.subscribe("mouse_click", function(button, _, y)
    recordInteraction()
    local updated = false
    if button == 1 and y > 1 and y < term_height then
        local item = filtered_index[scroll_pos + y - 2]
        if item and util.getItemKey(item) ~= util.getItemKey(selected_item) then
            for slot = 1, 15 do
                goal_inventory[slot] = util.itemWithCount(item, item.maxCount)
            end
            selected_item = item
            updated = true
        end
    end
    if not updated and selected_item then
        selected_item = nil
        setPreviewGoal()
        updated = true
    end
    if updated then
        renderScreen()
        readjust.notifyOne()
    end
end)
async.subscribe("mouse_scroll", function(direction)
    recordInteraction()
    scroll_pos = scroll_pos + direction * 3
    renderScreen()
end)

local function handleIndexUpdate()
    updateFilteredIndex()
    renderScreen()

    if search_query ~= "" then
        -- We don't want to rearrange existing items/slots in the inventory, since that can race
        -- with the user taking out items, but we can add to empty slots.
        local present_in_goal = {}
        for _, item in pairs(goal_inventory) do
            present_in_goal[util.getItemKey(item)] = true
        end
        local j = 1
        for i = 1, 15 do
            if not goal_inventory[i] then
                local item = filtered_index[j]
                while item and present_in_goal[util.getItemKey(item)] do
                    j = j + 1
                    item = filtered_index[j]
                end
                if item then
                    goal_inventory[i] = util.itemWithCount(item, item.maxCount)
                    j = j + 1
                end
            end
        end
    end

    -- Force readjustment regardless of whether the goal inventory was changed, since the available
    -- count might have changed for already existing items.
    readjust.notifyOne()
end

local inventory_adjusted = async.newNotify()
async.subscribe("turtle_inventory", readjust.notifyOne)
async.spawn(function()
    turtle.select(16)
    while true do
        if wired_name == nil then
            modem_connected.wait()
        end
        local current_inventory = async.parMap(util.iota(16), function(slot)
            return turtle.getItemDetail(slot, true)
        end)
        rednet.send(server_id, {
            type = "adjust_inventory",
            client = wired_name,
            current_inventory = current_inventory,
            goal_inventory = goal_inventory,
            preview = selected_item == nil,
        }, "purple_storage")
        async.timeout(1, inventory_adjusted.wait) -- timeout in case the modem is disconnected
        readjust.wait()
        recordInteraction()
    end
end)

async.spawn(function()
    while true do
        local computer_id, msg = rednet.receive("purple_storage")
        if msg.type == "inventory_adjusted" then
            server_id = computer_id
            inventory_adjusted.notifyOne()
        elseif msg.type == "request_inventory" then
            server_id = computer_id
            readjust.notifyOne()
        elseif msg.type == "patch_index" then
            server_id = computer_id
            if msg.reset then
                index = {}
            end
            for key, item in pairs(msg.items) do
                index[key] = item
            end
            fullness = msg.fullness
            -- The server sends `fullness` updates after every operation, even if it didn't touch
            -- any items -- make sure this doesn't cause an infinite loop.
            if next(msg.items) then
                handleIndexUpdate()
            else
                renderScreen()
            end
        elseif msg.type == "peripherals_changed" then
            local was_connected = wired_name ~= nil
            wired_name = modem.getNameLocal()
            local is_connected = wired_name ~= nil
            if is_connected and not was_connected then
                modem_connected.notifyOne()
            end
            if is_connected ~= was_connected then
                renderScreen()
            end
        end
    end
end)

rednet.send(server_id, { type = "request_index" }, "purple_storage")

-- Check modem status only after we subscribe to rednet, since otherwise we could miss
-- a notification.
wired_name = modem.getNameLocal()
if wired_name ~= nil then
    modem_connected.notifyOne()
end

async.drive()
