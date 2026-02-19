local async = {}

local tasks = {} -- { [task_id] = task }
local next_task_id = 1
local subscriptions = {} -- { [awaited_event_or_key] = { task_id, ... } }
local wildcard_subscriptions = {} -- { task_id, ... }
local rpc_subscriptions = { head = 1, tail = 1 } -- queue of task IDs
local woken_keys = { head = 1, tail = 1 } -- queue
local driven = false
local current_task_id = nil

function async.waitOn(key)
    if coroutine.yield(key) == "terminate" then
        error("Terminated")
    end
end

function async.wakeBy(key)
    woken_keys[woken_keys.tail] = key
    woken_keys.tail = woken_keys.tail + 1
end

local function resumeTask(task_id, ...)
    local task = tasks[task_id]
    if not task then
        -- The task was cancelled.
        return false
    end

    current_task_id = task_id
    local out = table.pack(coroutine.resume(task.coroutine, ...))
    local ok = out[1]
    local params = table.pack(table.unpack(out, 2, out.n))
    current_task_id = nil

    if not ok then
        error(params[1])
    end

    if coroutine.status(task.coroutine) == "dead" then
        task.result = params
        if task.parent then
            tasks[task.parent].children[task_id] = nil
        end
        for child_id, _ in pairs(task.children) do
            local child_task = tasks[child_id]
            child_task.parent = task.parent
            if task.parent then
                tasks[task.parent].children[child_id] = true
            end
        end
        tasks[task_id] = nil
        async.wakeBy(task_id)
        return true
    else
        local filter = params[1]
        -- Put remote calls to peripherals to a separate queue to resolve them more efficiently.
        --
        -- This check is very hacky, but it's pretty much the only option: we cannot trust
        -- `task_complete` subscriptions from any other source to be in the right order, and even
        -- overriding `peripheral.call` doesn't help, as there could be a coroutine in-between
        -- sending subscriptions at the wrong moment, breaking the entire event loop and not just
        -- itself.
        --
        -- Using `debug.getinfo` guarantees that the request originated from the true native code as
        -- opposed to `coroutine.yield`.
        if (
            filter == "task_complete"
            and debug.getinfo(task.coroutine, 1).source == "@/rom/apis/peripheral.lua"
        ) then
            -- When events come, we'll need to detect if we made any progress. Basically the only
            -- way to check that is to see if the active frame changed, and the only way to do that
            -- that I'm aware of is via a local. Choose the `name` parameter of `peripheral.call`,
            -- since it's not used after yielding.
            local name, value = debug.getlocal(task.coroutine, 1, 1)
            assert(name == "name", "unexpected local name")
            if value == "__purplesyringa_async_marker" then
                -- No progress, so no need to resubscribe -- we're still in queue.
                return false
            end
            debug.setlocal(task.coroutine, 1, 1, "__purplesyringa_async_marker")
            rpc_subscriptions[rpc_subscriptions.tail] = task_id
            rpc_subscriptions.tail = rpc_subscriptions.tail + 1
            return true
        elseif filter == nil then
            table.insert(wildcard_subscriptions, task_id)
            return true
        else
            if not subscriptions[filter] then
                subscriptions[filter] = {}
            end
            table.insert(subscriptions[filter], task_id)
            return true
        end
    end
end

local function spawn(closure, detached)
    local task_id = next_task_id
    next_task_id = next_task_id + 1

    local task = {
        coroutine = coroutine.create(function()
            local result = table.pack(xpcall(closure, debug.traceback))
            if result[1] then
                return table.unpack(result, 2, result.n)
            else
                error(result[2])
            end
        end),
        result = nil,
        children = {},
        parent = nil,
    }
    task.cancel = function()
        current_task_id = task_id
        coroutine.resume(task.coroutine, "terminate")
        current_task_id = nil
        task.coroutine = nil -- help GC
        task.result = {}
        if task.parent then
            tasks[task.parent].children[task_id] = nil
        end
        tasks[task_id] = nil
        async.wakeBy(task_id)
        for child_id, _ in pairs(task.children) do
            tasks[child_id].cancel()
        end
    end
    tasks[task_id] = task

    if not detached and current_task_id ~= nil then
        task.parent = current_task_id
        tasks[current_task_id].children[task_id] = true
    end

    resumeTask(task_id)

    return {
        finished = function()
            -- Avoid using `coroutine.status` here, since that doesn't capture cancellation.
            return task.result ~= nil
        end,
        join = function()
            if task.result == nil then
                async.waitOn(task_id)
            end
            return table.unpack(task.result, 1, task.result.n)
        end,
        cancel = task.cancel,
    }
end

function async.spawn(closure)
    return spawn(closure, false)
end

function async.spawnDetached(closure)
    return spawn(closure, true)
end

function async.newTaskSet(concurrency_limit)
    local semaphore = nil
    if concurrency_limit ~= nil then
        semaphore = async.newSemaphore(concurrency_limit)
    end
    local local_tasks = {}
    local next_id = 1
    return {
        spawn = function(closure)
            if semaphore then
                semaphore.acquire()
            end
            local id = next_id
            next_id = next_id + 1
            local task = async.spawn(function()
                local result = table.pack(pcall(closure))
                if semaphore then
                    semaphore.release()
                end
                local_tasks[id] = nil
                async.wakeBy(local_tasks)
                if result[1] then
                    return table.unpack(result, 2, result.n)
                else
                    error(result[2])
                end
            end)
            if not task.finished() then
                local_tasks[id] = task
            end
            return task
        end,
        join = function()
            for _, task in pairs(local_tasks) do
                task.join()
            end
        end,
        cancel = function()
            for _, task in pairs(local_tasks) do
                task.cancel()
            end
        end,
    }
end

local function deliverEvent(key, ...)
    local a = wildcard_subscriptions
    local b = subscriptions[key] or {}
    local woken_task_ids = table.move(a, 1, #a, #b + 1, b)
    wildcard_subscriptions = {}
    subscriptions[key] = nil
    for _, task_id in ipairs(woken_task_ids) do
        resumeTask(task_id, key, ...)
    end

    if key == "task_complete" then
        -- We know that only one task wants to handle this event, and we want to guess which one it
        -- is.
        --
        -- Since all native functions are synchronous, `task_complete` events arrive in the same
        -- order as async operations are scheduled. Since we only put coroutines yielding from
        -- within the official peripheral API in `rpc_subscriptions`, we can be certain that the
        -- orders match. Even if someone plays around with coroutines, they'll eventually have to
        -- call `coroutine.yield` manually to listen to the event, which puts the handler in
        -- `subscriptions` as opposed to `rpc_subscriptions`.
        --
        -- The task we're looking for is most likely the first one. It's not guaranteed to be such,
        -- since earlier tasks could lose their wake-ups. It can also just not be present in the
        -- list at all, e.g. if the task was cancelled or the user ran `command.execAsync`. But the
        -- common case is it's the first one, and that's what we optimize for.
        local i = rpc_subscriptions.head
        while i < rpc_subscriptions.tail and not resumeTask(rpc_subscriptions[i], key, ...) do
            i = i + 1
        end
        if i < rpc_subscriptions.tail then
            -- Found a matching task. Earlier tasks are guaranteed not to receive any updates, so we
            -- can remove them from the queue.
            while rpc_subscriptions.head <= i do
                rpc_subscriptions[rpc_subscriptions.head] = nil
                rpc_subscriptions.head = rpc_subscriptions.head + 1
            end
        end
    end
end

function async.drive()
    assert(not driven, "async runtime already running")
    driven = true

    while true do
        while woken_keys.head < woken_keys.tail do
            deliverEvent(woken_keys[woken_keys.head])
            woken_keys[woken_keys.head] = nil
            woken_keys.head = woken_keys.head + 1
        end
        if not next(tasks) then
            break
        end
        deliverEvent(os.pullEvent())
    end

    driven = false
end

function async.gather(task_list)
    for key, value in pairs(task_list) do
        if type(value) == "function" then
            task_list[key] = async.spawn(value)
        end
    end
    local out = {}
    for key, task in pairs(task_list) do
        out[key] = task.join()
    end
    return out
end

function async.race(task_list)
    local ready = { key = nil }
    local task_set = async.newTaskSet()
    for key, value in pairs(task_list) do
        local f
        if type(value) == "function" then
            f = value
        else
            f = value.join
        end
        task_set.spawn(function()
            local return_value = table.pack(f())
            if ready.key == nil then
                ready.key = key
                ready.value = return_value
                async.wakeBy(ready)
            end
        end)
    end
    -- If some task completes immediately, `ready` can already be populated.
    if ready.key == nil then
        async.waitOn(ready)
    end
    task_set.cancel()
    return ready.key, table.unpack(ready.value, 1, ready.value.n)
end

function async.timeout(duration, f)
    local result = table.pack(async.race({
        sleep = function()
            os.sleep(duration)
        end,
        f = f,
    }))
    local key = result[1]
    if key == "f" then
        return table.unpack(result, 2, result.n)
    end
end

function async.parMap(tbl, callback)
    local callbacks = {}
    for key, value in pairs(tbl) do
        callbacks[key] = function()
            return callback(value, key)
        end
    end
    return async.gather(callbacks)
end

function async.newRwLock(value)
    local n_readers = 0
    local has_writer = false
    local wait_reader = {}
    local wait_writer = {}

    local function makeGuard(unlock)
        local unlocked = false
        return setmetatable(
            {
                unlock = function()
                    assert(not unlocked, "guard already unlocked")
                    unlocked = true
                    unlock()
                end,
            },
            {
                __index = function(_, key)
                    assert(key == "value", "can only read property `value` of guard")
                    assert(not unlocked, "guard already unlocked")
                    return value
                end,
                __newindex = function(_, key, assigned_value)
                    assert(key == "value", "can only assign to property `value` of guard")
                    assert(not unlocked, "guard already unlocked")
                    value = assigned_value
                end,
            }
        )
    end

    return {
        shared = function()
            while has_writer do
                async.waitOn(wait_reader)
            end
            n_readers = n_readers + 1
            return makeGuard(function()
                n_readers = n_readers - 1
                if n_readers == 0 then
                    async.wakeBy(wait_writer)
                end
            end)
        end,
        unique = function()
            while n_readers > 0 or has_writer do
                async.waitOn(wait_writer)
            end
            has_writer = true
            return makeGuard(function()
                has_writer = false
                async.wakeBy(wait_reader)
                async.wakeBy(wait_writer)
            end)
        end,
    }
end

function async.newMutex(value)
    local rw_lock = async.newRwLock(value)
    return {
        lock = rw_lock.unique,
    }
end

function async.newSemaphore(value)
    local released = {}
    return {
        acquire = function()
            while value == 0 do
                async.waitOn(released)
            end
            value = value - 1
        end,
        release = function(delta)
            if delta == nil then
                delta = 1
            end
            assert(delta >= 0, "negative increment")
            assert(delta % 1 == 0, "float increment")
            if delta > 0 then
                value = value + delta
                async.wakeBy(released)
            end
        end,
    }
end

function async.newQueue()
    local queue = { head = 1, tail = 1 }
    return {
        get = function()
            while queue.head == queue.tail do
                async.waitOn(queue)
            end
            local values = queue[queue.head]
            queue[queue.head] = nil
            queue.head = queue.head + 1
            return table.unpack(values)
        end,
        put = function(...)
            queue[queue.tail] = table.pack(...)
            queue.tail = queue.tail + 1
            async.wakeBy(queue)
        end,
    }
end

function async.newNotifyOne()
    local permit = false
    local waiter = {}
    waiter.notifyOne = function()
        if not permit then
            permit = true
            async.wakeBy(waiter)
        end
    end
    waiter.wait = function()
        while not permit do
            async.waitOn(waiter)
        end
        permit = false
    end
    return waiter
end

function async.newNotifyWaiters()
    local waiter = {}
    waiter.notifyWaiters = function()
        async.wakeBy(waiter)
    end
    waiter.wait = function()
        async.waitOn(waiter)
    end
    return waiter
end

function async.subscribe(event, callback)
    async.spawn(function()
        while true do
            local args = table.pack(os.pullEvent(event))
            local coro = coroutine.create(function()
                callback(table.unpack(args, 2, args.n))
            end)
            local ok, err = coroutine.resume(coro)
            if not ok then
                error(err)
            end
            if coroutine.status(coro) ~= "dead" then
                error("event handlers must not yield")
            end
        end
    end)
end

return async
