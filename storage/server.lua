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
-- The server usually schedules all visible moves without yielding. This doesn't mean they will
-- occur within a single tick, since Lua code runs in a parallel thread, but it will look almost
-- immediate on good hardware. An exception is pulling from previews, which we discuss later.
--
-- # Storage
--
-- Items are stored in two places: the attached chests/bundles and the clients' inventories (to show
-- previews to users). The server can move preview items to another client if it needs them more.
--
-- Since users may racily change client inventories, we always interact with clients through
-- an emphemeral chest cell. This way we can inspect the type of the pulled item before depositing
-- it, and pull items back to storage if pushing fails. The server serializes operations, so the
-- index is never visible while items are in flight.

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
        --         chest_cells = {
        --             {
        --                 chest, -- wrapped chest inventory
        --                 slot,
        --                 count,
        --             },
        --             ...
        --         },
        --         bundles = {
        --             {
        --                 bundle, -- wrapped bundle inventory
        --                 count,
        --                 limit,
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
    local bundles = { peripheral.find("spectrum:bottomless_bundle") }

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
                            chest_cells = {},
                            bundles = {},
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
    async.parMap(bundles, function(bundle)
        local out = async.gather({
            item = util.bind(bundle.getItemDetail, 1),
            limit = util.bind(bundle.getItemLimit, 1),
        })
        if out.item then
            local key = util.getItemKey(out.item)
            if not index.items[key] then
                index.items[key] = {
                    item = out.item,
                    chest_cells = {},
                    bundles = {},
                }
            end
            table.insert(index.items[key].bundles, {
                bundle = bundle,
                count = out.item.count - 1, -- leave the indicator in place
                limit = out.limit - 1,
            })
        end
    end)

    -- Prefer to put non-full cells closer to the end so that they can be quickly located, added,
    -- or removed.
    for _, item_info in pairs(index.items) do
        table.sort(item_info.chest_cells, function(a, b)
            return a.count > b.count
        end)
    end

    -- Move matching items from chests to bundles.
    task_set = async.newTaskSet()
    total_parallel_cells = 0
    for _, item_info in pairs(index.items) do
        for _, bundle in pairs(item_info.bundles) do
            for i = #item_info.chest_cells, 1, -1 do
                if bundle.count == bundle.limit then
                    break
                end
                local chest_cell = item_info.chest_cells[i]
                local cur_limit = math.min(bundle.limit - bundle.count, chest_cell.count)
                bundle.count = bundle.count + cur_limit
                chest_cell.count = chest_cell.count - cur_limit
                if total_parallel_cells == 200 then
                    task_set.join()
                    task_set = async.newTaskSet()
                    total_parallel_cells = 0
                end
                total_parallel_cells = total_parallel_cells + 1
                task_set.spawn(function()
                    chest_cell.chest.pushItems(
                        peripheral.getName(bundle.bundle),
                        chest_cell.slot,
                        cur_limit
                    )
                end)
                if chest_cell.count == 0 then
                    item_info.chest_cells[i] = nil
                    table.insert(index.empty_cells, chest_cell)
                else
                    break
                end
            end
        end
    end
    task_set.join()

    return index
end

function Index:takeEmptyCell()
    local n = #self.empty_cells
    assert(n > 0, "out of storage")
    local empty_cell = self.empty_cells[n]
    self.empty_cells[n] = nil
    return empty_cell
end

function Index:importChestCell(input_cell, on_before_import)
    local input_item = input_cell.chest.getItemDetail(input_cell.slot)
    if not input_item then
        table.insert(self.empty_cells, input_cell)
        return nil
    end

    input_cell.count = input_item.count

    local key = util.getItemKey(input_item)
    if on_before_import then
        on_before_import(key)
    end

    if not self.items[key] then
        self.items[key] = {
            item = input_item,
            chest_cells = {},
            bundles = {},
        }
    end
    local item_info = self.items[key]

    -- Move items to bundles and other chest cells associated with the key to utilize space better.
    -- Don't pull into previews -- if a client wants that, it can request adjustment on an index
    -- update.
    for _, bundle in pairs(item_info.bundles) do
        local to_pull = math.min(bundle.limit - bundle.count, input_cell.count)
        if to_pull > 0 then
            input_cell.count = input_cell.count - to_pull
            bundle.count = bundle.count + to_pull
            async.spawn(function()
                bundle.bundle.pullItems(
                    peripheral.getName(input_cell.chest),
                    input_cell.slot,
                    to_pull
                )
            end)
        end
    end

    -- Force iteration in a specific order to maintain the count monotonicity invariant.
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

function Index:adjustInventory(client, current_inventory, goal_inventory, preview)
    -- The high-level logic here is:
    --
    -- 1. Move wrong inventory items to "holding" cells.
    -- 2. For each slot, pull insufficient items from inventory, chests, and previews. When pulling
    --    from chests and previews, we move items through holding cells. For previews, we validate
    --    that the type is what we expect.
    -- 3. Import items from holding cells. This accounts for failed moves and depositing items.
    --
    -- We need to be careful not to broadcast index updates for untouched items, since that would
    -- cause the client to trigger a retry, leading to an infinite loop without any useful work.

    -- Track keys whose counts were changed -- both total counts and counts accessible for preview
    -- (i.e. chests only). This is necessary because clients rely on index updates to trigger
    -- readjustment, which can fail due to items being in preview, even as the total count remains
    -- unchanged.
    --
    -- The key should always be touched *before* modifying its counts.
    local touched_keys = {}
    local function touchKey(key)
        if key ~= nil and touched_keys[key] == nil then
            touched_keys[key] = self:getItemCounts(key)
        end
    end

    local task_set = async.newTaskSet()

    -- Clear preview.
    for _, item in pairs(self.previews[client] or {}) do
        touchKey(util.getItemKey(item))
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
        touchKey(goal_key)
        local item_info = self.items[goal_key]

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
                -- If the input cell is now empty, don't delete it, since we still want to return it
                -- to storage.
            end
        end

        -- Try validated chests and bundles.
        if pushed < goal_item.count and item_info then
            -- Push through an empty cell. If pushing to client fails, we'll be able to reimport it.
            local output_cell = self:takeEmptyCell()

            -- Chests.
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

            -- Bundles. This happens after chests because, if an item is available in both
            -- locations, we'd rather free up finite chest space.
            for _, bundle in pairs(item_info.bundles) do
                if pushed == goal_item.count then
                    break
                end
                if bundle.count > 0 then
                    local cur_limit = math.min(goal_item.count - pushed, bundle.count)
                    pushed = pushed + cur_limit
                    bundle.count = bundle.count - cur_limit
                    task_set.spawn(util.bind(
                        bundle.bundle.pushItems,
                        peripheral.getName(output_cell.chest),
                        1,
                        cur_limit,
                        output_cell.slot
                    ))
                end
            end

            task_set.spawn(util.bind(pcall, function() -- protect against client disconnects
                output_cell.chest.pushItems(client, output_cell.slot, nil, slot_to)
            end))
            task_set.spawn(function()
                -- No need to touch the actual key here because we trust the chest, and so the key
                -- is `goal_key`, which we've already touched.
                self:importChestCell(output_cell)
            end)
        end

        if not preview then
            -- Try other clients' previews. We can't just schedule withdrawal and expect our client
            -- to ask again, since the original client might steal the items for preview, so this
            -- has to be blocking.
            for other_client, other_inventory in pairs(self.previews) do
                if pushed == goal_item.count then
                    break
                end
                for slot_from, other_item in pairs(other_inventory) do
                    if pushed == goal_item.count then
                        break
                    end
                    if util.getItemKey(other_item) == goal_key then
                        local tmp_cell = self:takeEmptyCell()
                        local cur_limit = math.min(goal_item.count - pushed, other_item.count)
                        pushed = pushed + cur_limit
                        task_set.spawn(util.bind(pcall, function() -- protect against client disconnects
                            tmp_cell.chest.pullItems(
                                other_client,
                                slot_from,
                                cur_limit,
                                tmp_cell.slot
                            )
                        end))
                        task_set.spawn(function()
                            local item = tmp_cell.chest.getItemDetail(tmp_cell.slot)
                            if item and util.getItemKey(item) == goal_key then
                                if item.count < cur_limit then
                                    -- The client must've had fewer items than we expected -- treat
                                    -- this as corruption.
                                    other_inventory[slot_from] = nil
                                    needs_retry = true
                                else
                                    other_item.count = other_item.count - item.count
                                    if other_item.count == 0 then
                                        other_inventory[slot_from] = nil
                                    end
                                end
                                async.spawn(function()
                                    tmp_cell.chest.pushItems(client, tmp_cell.slot, nil, slot_to)
                                end)
                            else
                                -- The other client's preview seems to be incorrect, possibly due to
                                -- a race or a disconnect. Either way, treat that specific item as
                                -- absent, since we haven't witnessed other corruption yet.
                                other_inventory[slot_from] = nil
                                needs_retry = true
                            end
                            -- If pulling from preview succeeds, we still don't know if pushing to
                            -- the client succeeds, so we just import the chest cell without
                            -- assuming anything. Note that if there was a race and we pulled
                            -- an unexpected item, it also needs to be touched!
                            self:importChestCell(tmp_cell, touchKey)
                        end)
                    end
                end
            end
        end

        if pushed > 0 then
            new_inventory[slot_to] = util.itemWithCount(goal_item, pushed)
        end

        ::next_goal_slot::
    end

    -- Import what the client wants to get rid of. This includes empty cells, since we want to
    -- return them to `empty_cells`.
    for _, input_cell in pairs(input_cells) do
        task_set.spawn(function()
            self:importChestCell(input_cell, touchKey)
        end)
    end

    -- Populate preview.
    if preview then
        self.previews[client] = new_inventory
    end

    task_set.join()

    -- Filter for actual changes before submitting index updates to avoid infinite loops.
    local changed_keys = {}
    for key, old_counts in pairs(touched_keys) do
        local new_counts = self:getItemCounts(key)
        if new_counts.total ~= old_counts.total or new_counts.preview ~= old_counts.preview then
            changed_keys[key] = true
        end
    end
    self:triggerKeysChanged(changed_keys)

    return new_inventory, needs_retry
end

function Index:getItemCounts(key)
    local item_info = self.items[key]
    if not item_info then
        return {
            preview = 0,
            total = 0,
        }
    end

    local preview_count = 0
    for _, inventory in pairs(self.previews) do
        for _, item in pairs(inventory) do
            if util.getItemKey(item) == key then
                preview_count = preview_count + item.count
            end
        end
    end

    local total_count = preview_count

    -- Chest cells are ordered by decreasing count, so if we iterate backwards, once we encounter
    -- a full stack, the rest must be also full.
    for i = #item_info.chest_cells, 1, -1 do
        local cell = item_info.chest_cells[i]
        if cell.count == item_info.item.maxCount then
            total_count = total_count + cell.count * i
            break
        else
            total_count = total_count + cell.count
        end
    end

    for _, bundle in pairs(item_info.bundles) do
        total_count = total_count + bundle.count
    end

    return {
        preview = preview_count,
        total = total_count,
    }
end

function Index:triggerKeysChanged(changed_keys)
    if not self.on_keys_changed then
        return
    end
    local items = {}
    for key, _ in pairs(changed_keys) do
        local item_info = self.items[key]
        if item_info then
            items[key] = util.itemWithCount(item_info.item, self:getItemCounts(key).total)
        end
    end
    self.on_keys_changed(items, self:getFullness())
end

function Index:formatIndex()
    local items = {}
    for key, item_info in pairs(self.items) do
        items[key] = util.itemWithCount(item_info.item, self:getItemCounts(key).total)
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
local function onPeripheralsChanged(name)
    if name:find("minecraft:chest_") == 1 or name:find("spectrum:bottomless_bundle_") == 1 then
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
