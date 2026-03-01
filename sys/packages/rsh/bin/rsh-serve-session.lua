local redirect = require "redirect"
local remote_events = require("rsh.events").remote_events
local svc = require "svc"
local vt = require "rsh.vt"

local params = textutils.unserialize(arg[1])

local function sendToClient(msg)
    msg.session = params.session
    rednet.send(params.client, msg, "rsh")
end

local function makeVt()
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
    local virtual_term = vt.newTerminalRedirect(handlers)
    virtual_term.setCursorPos(params.cursor_pos[1], params.cursor_pos[2])
    return virtual_term, op_queue
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

local virtual_term, op_queue = makeVt()

local function flushOpQueue()
    if next(op_queue) then
        sendToClient({ type = "term", ops = op_queue })
        -- We can't just write `op_queue = {}` because that will just overwrite the reference.
        for i, _ in pairs(op_queue) do
            op_queue[i] = nil
        end
    end
end

redirect.runWithEventSource(function()
    flushOpQueue()
    local event = table.pack(pullEventNetworked())
    if remote_events[event[1]] then
        sendToClient({ type = "ack" })
        -- The client adds dimension information to `term_resize` -- read it and make sure to remove
        -- it for consistency with base CraftOS.
        if event[1] == "term_resize" then
            params.size[1], params.size[2] = event[2], event[3]
            event = { "term_resize" }
        end
    end
    return table.unpack(event, 1, event.n)
end, function()
    redirect.runWithTerm(virtual_term, function()
        if not params.command[1] then
            params.command[1] = "msh"
        end
        local nested_shell = svc.makeNestedShell({ shell = shell })
        svc.reloadShellEnv(nested_shell)
        nested_shell.execute(table.unpack(params.command))
    end)
end)
flushOpQueue()

sendToClient({ type = "close", reason = "exit" }, "rsh")
