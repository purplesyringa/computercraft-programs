-- # Architecture overview
--
-- The protocol is based on an infinite "adjust inventory to goal" loop. The client listens to index
-- changes and `turtle_inventory` events, and when it receives one, asks the server to adjust the
-- inventory from a given state (the current inventory, loaded by the client) to a given state (the
-- goal inventory, determined by the client).
--
-- The client doesn't send a new request until the previous one completes. Note that when the server
-- adjusts the inventory, it will most likely move some items around, triggering `turtle_inventory`
-- again and retriggering the adjustment. This second adjustment will, on absence of races, not
-- touch any items and thus won't trigger a livelock.
--
-- However, if a race does arise, this swiftly resolves any inconsistencies. If the user modifies
-- the inventory at any point from the moment the client loads its current inventory to the point
-- when the server reports success, this will emit `turtle_inventory` and trigger an adjustment.
--
-- The server schedules all visible moves without yielding. This doesn't mean they will occur within
-- a single tick, since Lua code runs in a parallel thread, but it will look almost immediate on
-- good hardware.
--
-- # Storage
--
-- Items are stored in two places: the attached chests and the clients' inventories (to show
-- previews to users). The server can move preview items to another client if it needs them more.
--
-- Since users may racily change client inventories, we always interact with clients through
-- an emphemeral chest cell. This way we can inspect the type of the pulled item before depositing
-- it, and pull items back to storage if pushing fails.
--
-- This means that we momentarily don't know which items are actually present; to keep statistics
-- pretty, we treat such "ghost" items optimistically while in-flight. The clients are notified
-- whenever such delayed operations complete, so they can re-request adjustment if new items become
-- available.

local async = require "async"
local util = require "util"

peripheral.find("modem", rednet.open)

-- The index is considered valid by the point of the next action executed on the main thread. For
-- example, when `inventory.pushItems` is issued, the index is updated before `pushItems` completes,
-- since further operations will always see the new state, and the current-tick state is effectively
-- unobservable.
local Index = {}

Index.__index = Index

function Index:new(on_keys_changed)
    local index = setmetatable({
        -- Type: {
        --     [key] = {
        --         item, -- full item information, except `count`
        --         ghost_count, -- the number of in-flight items we assume to be in storage
        --         chest_cells = {
        --             {
        --                 chest, -- wrapped chest inventory
        --                 slot,
        --                 count,
        --             },
        --             ...
        --         },
        --     },
        --     ...
        -- }
        items = {},
        -- Type: {
        --     [client] = {
        --         [slot] = item,
        --         ...
        --     },
        --     ...
        -- }
        previews = {},
        -- Type: {
        --     {
        --         chest, -- wrapped chest inventory
        --         slot,
        --     },
        --     ...
        -- }
        empty_cells = {},
        on_keys_changed = on_keys_changed,
        total_cells = 0,
    }, self)

    local chests = { peripheral.find("minecraft:chest") }

    local task_set = async.newTaskSet()
    local total_parallel_cells = 0
    for _, chest in pairs(chests) do
        -- ComputerCraft limits the event queue to 256 events, so we have to batch requests. Set
        -- a slightly smaller limit to allow other events to be handled, e.g. rednet.
        if total_parallel_cells > 200 then
            task_set.join()
            task_set = async.newTaskSet()
            total_parallel_cells = 0
        end
        total_parallel_cells = total_parallel_cells + chest.size()
        index.total_cells = index.total_cells + chest.size()
        for slot = 1, chest.size() do
            task_set.spawn(function()
                local item = chest.getItemDetail(slot)
                if item then
                    local key = util.getItemKey(item)
                    if not index.items[key] then
                        index.items[key] = {
                            item = item,
                            ghost_count = 0,
                            chest_cells = {},
                        }
                    end
                    table.insert(index.items[key].chest_cells, {
                        chest = chest,
                        slot = slot,
                        count = item.count,
                    })
                else
                    table.insert(index.empty_cells, {
                        chest = chest,
                        slot = slot,
                    })
                end
            end)
        end
    end
    task_set.join()

    -- Prefer to put non-full cells closer to the end so that they can be quickly located, added,
    -- or removed.
    for _, item_info in pairs(index.items) do
        table.sort(item_info.chest_cells, function(a, b)
            return a.count > b.count
        end)
    end

    return index
end

function Index:takeEmptyCell()
    local n = #self.empty_cells
    assert(n > 0, "out of storage")
    local empty_cell = self.empty_cells[n]
    self.empty_cells[n] = nil
    return empty_cell
end

function Index:importChestCell(input_cell)
    local input_item = input_cell.chest.getItemDetail(input_cell.slot)
    if not input_item then
        table.insert(self.empty_cells, input_cell)
        return nil
    end

    input_cell.count = input_item.count

    local key = util.getItemKey(input_item)

    if not self.items[key] then
        self.items[key] = {
            item = input_item,
            ghost_count = 0,
            chest_cells = {},
        }
    end
    local item_info = self.items[key]

    -- Move items to other chest cells associated with the key to utilize space better. Don't pull
    -- into previews -- if a client wants that, it can request adjustment on an index update. Force
    -- iteration in a specific order to maintain the count monotonicity invariant.
    for _, output_cell in ipairs(item_info.chest_cells) do
        local to_pull = math.min(item_info.item.maxCount - output_cell.count, input_cell.count)
        if to_pull > 0 then
            input_cell.count = input_cell.count - to_pull
            output_cell.count = output_cell.count + to_pull
            async.spawn(function()
                output_cell.chest.pullItems(
                    peripheral.getName(input_cell.chest),
                    input_cell.slot,
                    to_pull,
                    output_cell.slot
                )
            end)
        end
    end

    if input_cell.count == 0 then
        table.insert(self.empty_cells, input_cell)
    else
        table.insert(item_info.chest_cells, input_cell)
    end

    return key
end

function Index:addGhostItems(item, count)
    local key = util.getItemKey(item)
    if not self.items[key] then
        self.items[key] = {
            item = item,
            ghost_count = 0,
            chest_cells = {},
        }
    end
    local item_info = self.items[key]
    item_info.ghost_count = item_info.ghost_count + count
end

function Index:removeGhostItems(item, count)
    local item_info = self.items[util.getItemKey(item)]
    item_info.ghost_count = item_info.ghost_count - count
end

function Index:adjustInventory(client, current_inventory, goal_inventory, preview)
    -- The high-level logic here is:
    --
    -- 1. Move wrong inventory items to "holding" cells.
    -- 2. For each slot, pull insufficient items from inventory, chests, and previews. When pulling
    --    from chests, we move items through a holding cell. When pulling from previews, we only
    --    schedule the pulling and don't wait for it; when it completes, we notify the client to
    --    retry.
    -- 3. Import items from holding cells. This accounts for failed moves and depositing items.
    --
    -- We need to be careful not to broadcast index updates for untouched items, since that would
    -- cause the client to trigger a retry, leading to an infinite loop without any useful work.

    local touched_keys = {}
    local function touchItem(item)
        local key = util.getItemKey(item)
        if touched_keys[key] == nil then
            touched_keys[key] = self:getItemCount(key)
        end
    end

    -- `changed_keys` plays two roles here. It tracks the items whose a) counts, b) ghost counts
    -- were changed. This is necessary because clients rely on index updates to trigger
    -- readjustment, which can fail due to items being in ghost state, even as the count is
    -- unaffected. So we emit updates for changed counts via `touched_keys`, but also forcibly for
    -- ghost items regardless of counts.
    local changed_keys = {}
    local task_set = async.newTaskSet()

    -- Clear preview.
    for _, item in pairs(self.previews[client] or {}) do
        touchItem(item)
    end
    self.previews[client] = nil

    -- Pull wrong/too many items.
    local input_cells = {}
    for slot_from, current_item in pairs(current_inventory) do
        local goal_item = goal_inventory[slot_from]
        local count_to_pull = nil
        local limit_to_pull
        if util.getItemKey(current_item) ~= util.getItemKey(goal_item) then
            count_to_pull = current_item.count
            limit_to_pull = nil
        elseif current_item.count > goal_item.count then
            count_to_pull = current_item.count - goal_item.count
            limit_to_pull = count_to_pull
        end
        if count_to_pull ~= nil then
            local input_cell = self:takeEmptyCell()
            input_cells[slot_from] = input_cell
            input_cell.count = count_to_pull
            task_set.spawn(util.bind(pcall, function() -- protect against client disconnects
                input_cell.chest.pullItems(client, slot_from, limit_to_pull, input_cell.slot)
            end))
        end
    end

    -- Push lacking items. Use ordered iteration to ensure that if an item with a small count is
    -- pulled into multiple slots, it's not scattered around.
    local new_inventory = {}
    local needs_retry = false
    for slot_to = 1, 16 do
        local goal_item = goal_inventory[slot_to]
        if not goal_item then
            goto next_goal_slot
        end
        local goal_key = util.getItemKey(goal_item)

        local pushed = 0
        local current_item = current_inventory[slot_to]
        if util.getItemKey(current_item) == goal_key then
            pushed = math.min(current_item.count, goal_item.count)
        end

        local function pushItems(cell_from, cell_to)
            local cur_limit = math.min(goal_item.count - pushed, cell_from.count)
            pushed = pushed + cur_limit
            cell_from.count = cell_from.count - cur_limit
            task_set.spawn(function()
                if cell_to then
                    local cell_to_name = peripheral.getName(cell_to.chest)
                    cell_from.chest.pushItems(cell_to_name, cell_from.slot, cur_limit, cell_to.slot)
                else
                    pcall(function() -- protect against client disconnects
                        cell_from.chest.pushItems(client, cell_from.slot, cur_limit, slot_to)
                    end)
                end
            end)
            return cell_from.count == 0
        end

        -- Try the current inventory.
        for slot_from, input_cell in pairs(input_cells) do
            if pushed == goal_item.count then
                break
            end
            local input_key = util.getItemKey(current_inventory[slot_from])
            if input_key == goal_key and input_cell.count > 0 then
                pushItems(input_cell)
                -- Don't delete the cell entirely, since we still want to return it.
            end
        end

        -- Try validated chests.
        local item_info = self.items[goal_key]
        if pushed < goal_item.count and item_info and next(item_info.chest_cells) then
            -- Push through an empty cell. If pushing to client fails, we'll be able to reimport it.
            local output_cell = self:takeEmptyCell()
            for i = #item_info.chest_cells, 1, -1 do
                if pushed == goal_item.count then
                    break
                end
                local chest_cell = item_info.chest_cells[i]
                if pushItems(chest_cell, output_cell) then
                    table.insert(self.empty_cells, chest_cell)
                    -- If this cell became empty, previous cells must have been emptied too, so
                    -- this has to be the last cell in the list.
                    item_info.chest_cells[i] = nil
                end
            end
            task_set.spawn(util.bind(pcall, function() -- protect against client disconnects
                output_cell.chest.pushItems(client, output_cell.slot, nil, slot_to)
            end))
            task_set.spawn(function()
                local actual_key = self:importChestCell(output_cell)
                -- If a push failed, there was a race, and we want to trigger a retry.
                if actual_key ~= nil then
                    changed_keys[actual_key] = true
                end
            end)
        end

        -- Populate expected inventory from `pushed` before trying to load other clients' previews,
        -- since that doesn't happen immediately.
        if pushed > 0 then
            touchItem(goal_item)
            new_inventory[slot_to] = util.itemWithCount(goal_item, pushed)
        end

        -- Try other clients' previews. We don't trust them, so instead of pushing immediately, we
        -- trigger the appropriate number of items to be withdrawn, and then rely on the client to
        -- re-request adjustment once that completes.
        if preview then
            goto next_goal_slot
        end
        for other_client, other_inventory in pairs(self.previews) do
            for slot_from, other_item in pairs(other_inventory) do
                if pushed == goal_item.count then
                    goto next_goal_slot
                end
                if util.getItemKey(other_item) == goal_key then
                    local tmp_cell = self:takeEmptyCell()
                    local cur_limit = math.min(goal_item.count - pushed, other_item.count)
                    pushed = pushed + cur_limit
                    other_item.count = other_item.count - cur_limit
                    if other_item.count == 0 then
                        other_inventory[slot_from] = nil
                    end
                    needs_retry = true
                    task_set.spawn(util.bind(pcall, function() -- protect against client disconnects
                        tmp_cell.chest.pullItems(
                            other_client,
                            slot_from,
                            cur_limit,
                            tmp_cell.slot
                        )
                    end))
                    task_set.spawn(function()
                        self:addGhostItems(other_item, cur_limit)
                        local actual_key = self:importChestCell(tmp_cell)
                        if actual_key ~= nil then
                            changed_keys[actual_key] = true
                        end
                        self:removeGhostItems(other_item, cur_limit)
                    end)
                end
            end
        end

        ::next_goal_slot::
    end

    -- Import what the client wants to get rid of. This includes empty cells, since we want to
    -- return them to `empty_cells`.
    for slot_from, input_cell in pairs(input_cells) do
        task_set.spawn(function()
            local ghost_count = input_cell.count
            local item = current_inventory[slot_from]
            self:addGhostItems(item, ghost_count)
            local actual_key = self:importChestCell(input_cell)
            if actual_key then
                changed_keys[actual_key] = true
            end
            self:removeGhostItems(item, ghost_count)
        end)
    end

    -- Populate preview.
    if preview then
        self.previews[client] = new_inventory
    end

    -- Filter for actual changes before submitting index updates to avoid infinite loops.
    for key, old_count in pairs(touched_keys) do
        if self:getItemCount(key) ~= old_count then
            changed_keys[key] = true
        end
    end

    task_set.join()

    self:triggerKeysChanged(changed_keys)

    return new_inventory, needs_retry
end

function Index:getItemCount(key)
    local item_info = self.items[key]
    if not item_info then
        return 0
    end
    local count = item_info.ghost_count
    for _, inventory in pairs(self.previews) do
        for _, item in pairs(inventory) do
            if util.getItemKey(item) == key then
                count = count + item.count
            end
        end
    end
    -- Chest cells are ordered by decreasing count, so if we iterate backwards, once we encounter
    -- a full stack, the rest must be also full.
    for i = #item_info.chest_cells, 1, -1 do
        local cell = item_info.chest_cells[i]
        if cell.count == item_info.item.maxCount then
            count = count + cell.count * i
            break
        else
            count = count + cell.count
        end
    end
    return count
end

function Index:triggerKeysChanged(changed_keys)
    if not self.on_keys_changed then
        return
    end
    local items = {}
    for key, _ in pairs(changed_keys) do
        local item_info = self.items[key]
        if item_info then
            items[key] = util.itemWithCount(item_info.item, self:getItemCount(key))
        end
    end
    self.on_keys_changed(items, self:getFullness())
end

function Index:formatIndex()
    local items = {}
    for key, item_info in pairs(self.items) do
        items[key] = util.itemWithCount(item_info.item, self:getItemCount(key))
    end
    return items
end

function Index:getFullness()
    return math.ceil((self.total_cells - #self.empty_cells) / self.total_cells * 100)
end

-- `adjustInventory` alone gets pretty close to exhausting the 256 event limit, so we serialize all
-- queue operations. This also includes reindexing.
local index = async.newMutex(nil)

local function broadcastPatchIndex(items, reset, fullness)
    rednet.broadcast({
        type = "patch_index",
        items = items,
        reset = reset,
        fullness = fullness,
    }, "purple_storage")
end

-- Use notify to avoid reindexing several times when multiple peripherals are (dis)connected.
local reindex = async.newNotifyOne()
function onPeripheralsChanged(name)
    if name:find("minecraft:chest_") == 1 then
        reindex.notifyOne()
    end
    if name:find("turtle_") == 1 then
        -- Notify clients that they might have been accidentally connected/disconnected and need to
        -- check their state.
        rednet.broadcast({ type = "peripherals_changed" }, "purple_storage")
    end
end
async.subscribe("peripheral", onPeripheralsChanged)
async.subscribe("peripheral_detach", onPeripheralsChanged)
async.spawn(function()
    while true do
        local index = index.lock()
        index.value = Index:new(function(items, fullness)
            broadcastPatchIndex(items, false, fullness)
        end)
        broadcastPatchIndex(index.value:formatIndex(), true, index.value:getFullness())
        -- Ask clients to submit their inventories, since we can't index them otherwise.
        rednet.broadcast({ type = "request_inventory" }, "purple_storage")
        index.unlock()
        reindex.wait()
    end
end)

async.spawn(function()
    while true do
        local computer_id, msg = rednet.receive("purple_storage")
        async.spawn(function()
            local index = index.lock()
            local response
            if msg.type == "adjust_inventory" then
                local new_inventory, needs_retry = index.value:adjustInventory(
                    msg.client,
                    msg.current_inventory,
                    msg.goal_inventory,
                    msg.preview
                )
                response = {
                    type = "inventory_adjusted",
                    new_inventory = new_inventory,
                    needs_retry = needs_retry,
                }
            elseif msg.type == "request_index" then
                response = {
                    type = "patch_index",
                    items = index.value:formatIndex(),
                    reset = true,
                    fullness = index.value:getFullness(),
                }
            elseif msg.type == "ping" then
                -- It is important that this happens under a lock, even though it doesn't access the
                -- data, so that the timeout resolution algorithm from README works properly.
                response = {
                    type = "pong",
                    id = msg.id,
                }
            end
            if response then
                rednet.send(computer_id, response, "purple_storage")
            end
            index.unlock()
        end)
    end
end)

async.drive()
