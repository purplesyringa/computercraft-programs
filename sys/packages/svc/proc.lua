local proc = {}

local processes = {} -- { [pid] = { name, coroutine, filter, on_killed } }
local next_process_id = 1

local function deliverEvent(pid, ...)
    local process = processes[pid]
    local out = table.pack(coroutine.resume(process.coroutine, ...))
    if coroutine.status(process.coroutine) == "dead" then
        processes[pid] = nil
    else
        process.filter = out[2]
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
    deliverEvent(pid)
    return pid
end

function proc.stop(pid)
    os.queueEvent("stop_process", pid)
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

local interactive_events = {
    terminate = true,
    char = true,
    key = true,
    key_up = true,
    mouse_click = true,
    mouse_drag = true,
    mouse_scroll = true,
    mouse_up = true,
    paste = true,
    term_resize = true,
}

function proc.loop()
    while true do
        local event = table.pack(os.pullEventRaw())
        if event[1] == "stop_process" then
            local _, pid = table.unpack(event)
            if processes[pid] then
                -- `hangup` means that the program should assume it's no longer needed and quit
                -- entirely. This is different for shells, which otherwise typically forward
                -- `terminate` to running children and don't exit by default.
                deliverEvent(pid, "terminate", "hangup")
            end
        else
            if event[1] == "terminate" then
                -- Don't terminate all processes, instead treat this as a key press that processes
                -- can decide how to handle on a best-effort basis. `getty` rewrites this to
                -- `terminate`.
                event[1] = "fg_terminate"
            end
            for pid, process in pairs(processes) do
                if process.filter == event[1] or process.filter == nil then
                    deliverEvent(pid, table.unpack(event, 1, event.n))
                end
            end
        end
    end
end

return proc
