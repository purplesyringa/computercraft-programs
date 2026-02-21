local proc = {}

local processes = {} -- { [key] = { coroutine, filter, is_foreground, on_killed } }
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

function proc.start(f, on_killed, is_foreground)
    local pid = next_process_id
    next_process_id = next_process_id + 1
    processes[pid] = {
        coroutine = coroutine.create(f),
        filter = nil,
        is_foreground = is_foreground or false,
        on_killed = on_killed,
    }
    deliverEvent(pid)
    return pid
end

function proc.terminate(pid)
    os.queueEvent("terminate_process", pid)
end

function proc.kill(pid)
    local process = processes[pid]
    processes[pid] = nil
    if process.on_killed then
        process.on_killed()
    end
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
        if event[1] == "terminate_process" then
            local _, pid = table.unpack(event)
            if processes[pid] then
                deliverEvent(pid, "terminate")
            end
        else
            for pid, process in pairs(processes) do
                local matches = (
                    process.filter == event[1]
                    or process.filter == nil
                    or event[1] == "terminate"
                )
                if interactive_events[event[1]] then
                    matches = matches and process.is_foreground
                end
                if matches then
                    deliverEvent(pid, table.unpack(event, 1, event.n))
                end
            end
        end
    end
end

return proc
