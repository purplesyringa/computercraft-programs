local function runWithTerm(redirect_term, redirect_seat, f, ...)
    local coro = coroutine.create(f)
    local event = table.pack(...)
    while true do
        local old_term, old_seat = term.current(), term._seat
        term.redirect(redirect_term)
        term._seat = redirect_seat
        local out = table.pack(coroutine.resume(coro, table.unpack(event, 1, event.n)))
        if not out[1] then
            printError(out[2])
        end
        -- Reload `redirect_term` because the process might have set up its own terminal redirect.
        redirect_term, redirect_seat = term.current(), term._seat
        term.redirect(old_term)
        term._seat = old_seat
        if coroutine.status(coro) == "dead" then
            break
        end
        local filter = out[2]
        repeat
            event = table.pack(os.pullEventRaw())
        until event[1] == filter or filter == nil or event[1] == "terminate"
    end
end

local function runWithEventSource(f, ...)
    local coro = coroutine.create(f)
    local ok, filter = coroutine.resume(coro, ...)
    assert(ok, filter)
    return {
        pushEvent = function(name, ...)
            if (
                coroutine.status(coro) ~= "dead"
                and (name == filter or filter == nil or name == "terminate")
            ) then
                ok, filter = coroutine.resume(coro, name, ...)
                assert(ok, filter)
            end
        end,
        isDead = function()
            return coroutine.status(coro) == "dead"
        end,
    }
end

return {
    runWithTerm = runWithTerm,
    runWithEventSource = runWithEventSource,
}
