local function runWithTerm(redirect, f, ...)
    local coro = coroutine.create(f)
    local event = table.pack(...)
    while true do
        local old_term = term.current()
        term.redirect(redirect)
        local out = table.pack(coroutine.resume(coro, table.unpack(event, 1, event.n)))
        if not out[1] then
            printError(out[2])
        end
        -- Reload `redirect` because the process might have set up its own terminal redirect.
        redirect = term.current()
        term.redirect(old_term)
        if not out[1] or coroutine.status(coro) == "dead" then
            break
        end
        local filter = out[2]
        repeat
            event = table.pack(os.pullEventRaw())
        until event[1] == filter or filter == nil or event[1] == "terminate"
    end
end

local function runWithEventSource(pullEvent, f, ...)
    local coro = coroutine.create(f)
    local event = table.pack(...)
    while true do
        local out = table.pack(coroutine.resume(coro, table.unpack(event, 1, event.n)))
        if not out[1] then
            error(out[2])
        end
        if coroutine.status(coro) == "dead" then
            break
        end
        local filter = out[2]
        repeat
            event = table.pack(pullEvent())
        until event[1] == filter or filter == nil or event[1] == "terminate"
    end
end

return {
    runWithTerm = runWithTerm,
    runWithEventSource = runWithEventSource,
}
