local proc = {}

local processes = {} -- { [pid] = { name, coroutine, filter, on_killed } }
local next_process_id = 1
local processes_to_start = {}
local processes_to_stop = {}
local imminent_handlers = setmetatable({}, { __weak = "v" })

local function deliverEvent(pid, ...)
    local process = processes[pid]
    local out = table.pack(coroutine.resume(process.coroutine, ...))
    if coroutine.status(process.coroutine) == "dead" then
        processes[pid] = nil
    else
        process.filter = out[2]
    end
end

local function deliverEventToAll(name, ...)
    for pid, process in pairs(processes) do
        if process.filter == name or process.filter == nil then
            deliverEvent(pid, name, ...)
        end
    end
end

function proc.start(name, f, on_killed)
    local pid = next_process_id
    next_process_id = next_process_id + 1
    processes[pid] = {
        name = name,
        coroutine = coroutine.create(f),
        filter = nil,
        on_killed = on_killed,
    }
    table.insert(processes_to_start, pid)
    return pid
end

function proc.stop(pid)
    table.insert(processes_to_stop, pid)
end

function proc.kill(pid)
    local process = processes[pid]
    processes[pid] = nil
    if process and process.on_killed then
        process.on_killed()
    end
end

function proc.list()
    local result = {}
    for pid, process in pairs(processes) do
        table.insert(result, {
            pid = pid,
            name = process.name,
        })
    end
    table.sort(result, function(a, b)
        return a.pid < b.pid
    end)
    return result
end

function proc.loop(recovery_cb)
    local alt_held = false
    while true do
        for _, pid in ipairs(processes_to_start) do
            if processes[pid] then
                deliverEvent(pid)
            end
        end
        processes_to_start = {}

        for _, pid in ipairs(processes_to_stop) do
            if processes[pid] then
                -- `hangup` means that the program should assume it's no longer needed and quit
                -- entirely. This is different for shells, which otherwise typically forward
                -- `terminate` to running children and don't exit by default.
                deliverEvent(pid, "terminate", "hangup")
            end
        end
        processes_to_stop = {}

        local event = table.pack(os.pullEventRaw())
        if event[1] == "terminate" and not event[2] and alt_held then
            recovery_cb()
        else
            if event[1] == "key" and event[2] == keys.leftAlt and not event[3] then
                alt_held = true
            elseif event[1] == "key_up" and event[2] == keys.leftAlt and not event[3] then
                alt_held = false
            elseif event[1] == "terminate" then
                -- Don't terminate all processes, instead treat this as a key press that processes
                -- can decide how to handle on a best-effort basis. `getty` rewrites this to
                -- `terminate`.
                event[1] = "fg_terminate"
            end
            deliverEventToAll(table.unpack(event, 1, event.n))
        end
    end
end

function proc.registerRebootShutdownHandlers()
    for _, method in pairs({ "reboot", "shutdown" }) do
        local old_method = os[method]
        os[method] = function()
            -- Code after `os.reboot/shutdown` is typically unreachable, but neither
            -- `coroutine.yield` nor `error` can implement these semantics in presence of `parallel`
            -- and `pcall`. So instead of setting a flag and unwinding, we execute logic here.
            --
            -- Give all programs a chance to handle going down. We can't just deliver an event to
            -- processes here, because processes are not reentrant, and so programs running within
            -- the current process (e.g. those across a `multishell` tab) wouldn't be able to react.
            for handler, _ in pairs(imminent_handlers) do
                -- Don't let handlers prevent shutdown -- that would make remotely updating broken
                -- software unnecessarily difficult.
                pcall(handler, method)
            end
            old_method()
            error("unreachable")
        end
    end
end

function proc.withImminentHandler(handler, f, ...)
    assert(not imminent_handlers[handler], "handler already registered")
    -- Make the entry weak by coroutine so that abandoned coroutines aren't kept alive forever.
    imminent_handlers[handler] = coroutine.running()
    local result = table.pack(pcall(f, ...))
    imminent_handlers[handler] = nil
    if result[1] then
        return table.unpack(result, 2, result.n)
    else
        error(result[2], 0)
    end
end

return proc
