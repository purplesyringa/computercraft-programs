local async = require "async"
local named = require "named"
local remote_events = require("rsh.events").remote_events
local vt = require "rsh.vt"

local function startProgram(program, ...)
    -- Even if we want to run a specific command, we need to run it inside a shell to give it
    -- an environment. But running `shell <program>` doesn't invoke the ROM startup script, which is
    -- actually responsible for setting up the environment, so we have to invoke ourselves as
    -- a proxy to invoke the ROM startup script first and the requested command second.
    local command = {}
    if program ~= nil then
        command = { shell.getRunningProgram(), "--serve", program, ... }
    end

    -- The ROM startup script not only sets up the environment, but also runs MOTD and startup
    -- scripts from disks and the filesystem root, so we have to monkey-patch `settings.get` to
    -- disable that behavior.
    local one_time_overrides = {
        ["shell.allow_startup"] = false,
        ["shell.allow_disk_startup"] = false,
    }
    -- Leave MOTD when starting the shell normally.
    if program ~= nil then
        one_time_overrides["motd.enable"] = false
    end
    os.run(
        {
            _G = setmetatable({
                settings = setmetatable({
                    get = function(name, ...)
                        if one_time_overrides[name] ~= nil then
                            local value = one_time_overrides[name]
                            one_time_overrides[name] = nil
                            return value
                        end
                        return settings.get(name, ...)
                    end,
                }, { __index = settings }),
            }, { __index = _G }),

            -- This is breathtakingly idiotic, but I have no idea what else to do. CC's shell
            -- does not allow the prompt to be configured in any way, and it's really easy to
            -- get lost if the hostname is not mentioned, and this is the only place where we
            -- can inject our logic.
            write = function(text)
                local info = debug.getinfo(2)
                -- Notably, if rsh sessions are nested, only the innermost one will see `write`
                -- being called from `show_prompt` -- others will see the call to `write` from this
                -- function instead.
                if info.source == "@/rom/programs/shell.lua" and info.name == "show_prompt" then
                    local color = term.getTextColor()
                    term.setTextColor(colors.green)
                    write(named.hostname() .. " ")
                    term.setTextColor(color)
                end
                write(text)
            end,
        },
        "rom/programs/shell.lua",
        table.unpack(command)
    )
end

if arg[1] == "--serve" then
    shell.execute("rom/startup.lua")
    shell.execute(table.unpack(arg, 2))
    return
end

local function serveSession(client_id, params, event_queue)
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

    local coro = coroutine.create(function()
        startProgram(table.unpack(params.command, 1, params.command.n))
    end)

    local event = {}
    while true do
        local old_term = term.current()
        term.redirect(redirect)
        local out = table.pack(coroutine.resume(coro, table.unpack(event, 1, event.n)))
        if not out[1] then
            printError(out[2])
        end
        redirect = term.current()
        term.redirect(old_term)

        if next(op_queue) then
            rednet.send(client_id, {
                type = "term",
                session = params.session,
                ops = op_queue,
            }, "rsh")
        end
        op_queue = {}

        if not out[1] or coroutine.status(coro) == "dead" then
            break
        end
        local filter = out[2]
        repeat
            event = table.pack(event_queue.get())
            if remote_events[event[1]] then
                rednet.send(client_id, { type = "ack", session = params.session }, "rsh")
                -- The client adds dimension information to `term_resize` -- read it and make sure
                -- to remove it for consistency with base CraftOS.
                if event[1] == "term_resize" then
                    size_x, size_y = event[2], event[3]
                    event = { "term_resize" }
                end
            end
        until event[1] == filter or filter == nil or event[1] == "terminate"
    end

    rednet.send(client_id, {
        type = "close",
        session = params.session,
        reason = "exit",
    }, "rsh")
end

local open_sessions = {}

local function openSession(client_id, params)
    local event_queue = async.newQueue()

    local task = async.spawn(function()
        serveSession(client_id, params, event_queue)
        open_sessions[params.session] = nil
    end)

    if not task.finished() then
        open_sessions[params.session] = {
            task = task,
            event_queue = event_queue,
            client_id = client_id,
        }
    end
end

async.spawn(function()
    while true do
        local event = table.pack(os.pullEvent())
        if not remote_events[event[1]] then
            for _, session in pairs(open_sessions) do
                session.event_queue.put(table.unpack(event, 1, event.n))
            end
        end
    end
end)

async.spawn(function()
    rednet.host("rsh", named.hostname())
    while true do
        local client_id, msg = rednet.receive("rsh")
        if msg.type == "open" then
            openSession(client_id, msg)
        elseif msg.type == "event" then
            local session = open_sessions[msg.session]
            if session == nil then
                rednet.send(client_id, {
                    type = "server_reset",
                    session = msg.session,
                }, "rsh")
            else
                session.event_queue.put(table.unpack(msg.event, 1, msg.event.n))
            end
        elseif msg.type == "kill" then
            local session = open_sessions[msg.session]
            if session ~= nil then
                session.task.cancel()
                open_sessions[msg.session] = nil
            end
        end
    end
end)

local function closeAll(reason)
    for session_id, session in pairs(open_sessions) do
        rednet.send(session.client_id, {
            type = "close",
            session = session_id,
            reason = reason,
        }, "rsh")
    end
end

local old_reboot = os.reboot
os.reboot = function()
    closeAll("reboot")
    old_reboot()
end

local old_shutdown = os.shutdown
os.shutdown = function()
    closeAll("shutdown")
    old_shutdown()
end

async.subscribe("terminate", function()
    os.reboot = old_reboot
    os.shutdown = old_shutdown
    closeAll("terminate")
end)

async.drive()
