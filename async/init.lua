local async = {}

local tasks = {} -- { [task_id] = task }
local next_task_id = 1
local subscriptions = {} -- { [awaited_event_or_key] = { task, ... } }
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
        return
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
        for child_id, _ in task.children do
            local child_task = tasks[child_id]
            child_task.parent = task.parent
            if task.parent then
                tasks[task.parent].children[child_id] = true
            end
        end
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
        cancel = function()
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
            for child_id, _ in task.children do
                tasks[child_id].cancel()
            end
        end,
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
                semaphore.release()
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
        lock = rw_lock.write,
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
