local remote_events = require("rsh.events").remote_events
local svc = require "svc"
local vt = require "rsh.vt"

local params = textutils.unserialize(arg[1])

local function sendToClient(msg)
    msg.session = params.session
    rednet.send(params.client, msg, "rsh")
end

local function makeRedirect()
    local size_x, size_y = params.size[1], params.size[2]
    local handlers = {
        isColor = function() return params.is_color end,
        getSize = function() return size_x, size_y end,
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
    -- The shell PATH changes depending on whether the connected terminal is advanced, which can
    -- change across network, so we need to reinitialize it. The ROM startup script is responsible
    -- for this, but it also runs MOTD and startup scripts from disks and the filesystem root, so we
    -- have to monkey-patch `settings.get` to disable that behavior.
    local overrides = {
        ["shell.allow_startup"] = false,
        ["shell.allow_disk_startup"] = false,
        ["motd.enable"] = false,
    }
    os.run({
        shell = nested_shell,
        -- `startup.lua` requires various built-in modules; this is close enough.
        require = require,
        settings = setmetatable({
            get = function(name, ...)
                if overrides[name] ~= nil then
                    return overrides[name]
                end
                return settings.get(name, ...)
            end,
        }, { __index = settings }),
    }, "rom/startup.lua")
    -- Since `startup.lua` overrides path, we have to inject the combined /bin back.
    nested_shell.setPath("/" .. svc.getCombinedBinPath() .. ":" .. nested_shell.path())
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
        -- We can't just write `op_queue = {}` because that will just ovewrite the reference.
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
                size_x, size_y = event[2], event[3]
                event = { "term_resize" }
            end
        end
    until event[1] == filter or filter == nil or event[1] == "terminate"
    resume_args = event
end

sendToClient({ type = "close", reason = "exit" }, "rsh")
