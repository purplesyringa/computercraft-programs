local remote_events = require("rsh.events").remote_events
local svc = require "svc"
local vt = require "rsh.vt"

local params = textutils.unserialize(arg[1])

local function sendToClient(msg)
    msg.session = params.session
    rednet.send(params.client, msg, "rsh")
end

local function makeRedirect()
    local handlers = {
        isColor = function() return params.is_color end,
        getSize = function() return params.size[1], params.size[2] end,
    }
    local op_queue = {}
    for _, name in pairs({
        "setCursorPos",
        "setCursorBlink",
        "setTextColor",
        "setBackgroundColor",
        "setPaletteColor",
        "clear",
        "clearLine",
        "scroll",
        "write",
        "blit",
    }) do
        handlers[name] = function(...)
            table.insert(op_queue, table.pack(name, ...))
        end
    end
    local redirect = vt.newTerminalRedirect(handlers)
    redirect.setCursorPos(params.cursor_pos[1], params.cursor_pos[2])
    return redirect, op_queue
end

local function startProgram(program, ...)
    local nested_shell = svc.makeNestedShell({ shell = shell })
    svc.reloadShellEnv(nested_shell)
    nested_shell.execute(program or "msh", ...)
end

local function pullEventNetworked()
    while true do
        local event = table.pack(os.pullEventRaw())
        if event[1] == "terminate" then
            sendToClient({ type = "close", reason = "terminate" }, "rsh")
            error("Terminated", 0)
        elseif event[1] == "rednet_message" then
            local client_id, msg, protocol = event[2], event[3], event[4]
            if (
                protocol == "rsh"
                and client_id == params.client
                and msg.session == params.session
            ) then
                if msg.type == "event" then
                    return table.unpack(msg.event, 1, msg.event.n)
                elseif msg.type == "kill" then
                    error("Killed")
                end
            end
        end
        if not remote_events[event[1]] then
            return table.unpack(event, 1, event.n)
        end
    end
end

local redirect, op_queue = makeRedirect()
local coro = coroutine.create(startProgram)
local resume_args = params.command

while true do
    local old_term = term.current()
    term.redirect(redirect)
    local out = table.pack(coroutine.resume(coro, table.unpack(resume_args, 1, resume_args.n)))
    if not out[1] then
        printError(out[2])
    end
    -- Reload `redirect` because the process might have set up its own terminal redirect.
    redirect = term.current()
    term.redirect(old_term)

    if next(op_queue) then
        sendToClient({ type = "term", ops = op_queue })
        -- We can't just write `op_queue = {}` because that will just overwrite the reference.
        for i, _ in pairs(op_queue) do
            op_queue[i] = nil
        end
    end

    if not out[1] or coroutine.status(coro) == "dead" then
        break
    end

    local event
    local filter = out[2]
    repeat
        event = table.pack(pullEventNetworked())
        if remote_events[event[1]] then
            sendToClient({ type = "ack" })
            -- The client adds dimension information to `term_resize` -- read it and make sure
            -- to remove it for consistency with base CraftOS.
            if event[1] == "term_resize" then
                params.size[1], params.size[2] = event[2], event[3]
                event = { "term_resize" }
            end
        end
    until event[1] == filter or filter == nil or event[1] == "terminate"
    resume_args = event
end

sendToClient({ type = "close", reason = "exit" }, "rsh")
