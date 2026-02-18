local async = {}

local tasks = {} -- { [task_id] = task }
local next_task_id = 1
local subscriptions = {} -- { [awaited_event_or_key] = { task, ... } }
local woken_keys = { head = 1, tail = 1 } -- queue

function async.waitOn(key)
    coroutine.yield(key)
end

function async.wakeBy(key)
    woken_keys[woken_keys.tail] = key
    woken_keys.tail = woken_keys.tail + 1
end

local function resumeTask(task_id, ...)
    local task = tasks[task_id]
    if not task then
        -- The task was cancelled.
        return
    end

    local out = table.pack(coroutine.resume(task.coroutine, ...))
    local ok = out[1]
    local params = table.pack(table.unpack(out, 2, out.n))

    if not ok then
        error(params[1])
    end

    if coroutine.status(task.coroutine) == "dead" then
        task.result = params
        tasks[task_id] = nil
        async.wakeBy(task_id)
    else
        local filter = params[1]
        if filter == nil then
            filter = "any"
        end
        if not subscriptions[filter] then
            subscriptions[filter] = {}
        end
        table.insert(subscriptions[filter], task_id)
    end
end

function async.spawn(closure)
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
    }
    tasks[task_id] = task
    resumeTask(task_id)

    return {
        join = function()
            -- Avoid using `coroutine.status` here, since that doesn't capture cancellation.
            if task.result == nil then
                async.waitOn(task_id)
            end
            return table.unpack(task.result, 1, task.result.n)
        end,
        cancel = function()
            task.coroutine = nil -- help GC
            task.result = {}
            tasks[task_id] = nil
            async.wakeBy(task_id)
        end,
    }
end

function async.newTaskSet(concurrency_limit)
    local local_tasks = {}
    local n_active_tasks = 0
    local next_id = 1
    return {
        spawn = function(closure)
            -- This works correctly for `concurrency_limit = nil`.
            while n_active_tasks == concurrency_limit do
                async.waitOn(local_tasks)
            end
            local id = next_id
            next_id = next_id + 1
            n_active_tasks = n_active_tasks + 1
            local task = async.spawn(function()
                closure()
                local_tasks[id] = nil
                n_active_tasks = n_active_tasks - 1
                async.wakeBy(local_tasks)
            end)
            if task.result == nil then
                local_tasks[id] = task
            end
        end,
        join = function()
            for _, task in pairs(local_tasks) do
                task.join()
            end
        end,
    }
end

local function deliverEvent(key, ...)
    assert(key ~= "any", "event `any` is invalid")
    local a = subscriptions.any or {}
    local b = subscriptions[key] or {}
    local woken_task_ids = table.move(a, 1, #a, #b + 1, b)
    subscriptions.any = nil
    subscriptions[key] = nil
    for _, task_id in ipairs(woken_task_ids) do
        resumeTask(task_id, key, ...)
    end
end

function async.drive()
    while true do
        while woken_keys.head < woken_keys.tail do
            deliverEvent(woken_keys[woken_keys.head])
            woken_keys[woken_keys.head] = nil
            woken_keys.head = woken_keys.head + 1
        end
        if not next(tasks) then
            return
        end
        deliverEvent(os.pullEvent())
    end
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
    local spawned_tasks = {}
    for key, value in pairs(task_list) do
        local f
        if type(value) == "function" then
            f = value
        else
            f = value.join
        end
        table.insert(spawned_tasks, async.spawn(function()
            local return_value = table.pack(f())
            if ready.key == nil then
                ready.key = key
                ready.value = return_value
                async.wakeBy(ready)
            end
        end))
    end
    -- If some task completes immediately, `ready` can already be populated.
    if ready.key == nil then
        async.waitOn(ready)
    end
    for _, task in pairs(spawned_tasks) do
        task.cancel()
    end
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
        read = function()
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
        write = function()
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
        force = function()
            assert(n_readers == 0 and not has_writer, "mutex locked")
            return value
        end,
    }
end

function async.newMutex(value)
    local rw_lock = async.newRwLock(value)
    return {
        lock = rw_lock.write,
        force = rw_lock.force,
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
            async.spawn(function()
                callback(table.unpack(args, 2, args.n))
            end)
        end
    end)
end

return async
