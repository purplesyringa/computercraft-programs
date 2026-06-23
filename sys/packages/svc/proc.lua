local proc = {}

local processes = {} -- { [pid] = { name, coroutine, filter, on_killed } }
local next_process_id = 1
local running_process_id = nil
local processes_to_start = {}
local processes_to_stop = {}

local function deliverEvent(pid, ...)
    running_process_id = pid
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

function proc.loop()
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
        if event[1] == "terminate" then
            -- Don't terminate all processes, instead treat this as a key press that processes can
            -- decide how to handle on a best-effort basis. `getty` rewrites this to `terminate`.
            event[1] = "fg_terminate"
        end
        deliverEventToAll(table.unpack(event, 1, event.n))
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
            -- Deliver an event to all processes except the currently running one: that's both
            -- expected because the code in the process should be unreachable, and necessary because
            -- we can't resume a running coroutine.
            processes[running_process_id].filter = ""
            deliverEventToAll(method .. "_imminent")
            old_method()
            error("unreachable")
        end
    end
end

return proc
