dofile(fs.combine(shell.getRunningProgram(), "../../pkgs.lua"))
local async = require "async"
local named = require "named"
local remote_events = require("events").remote_events
local vt = require "vt"

local function startProgram(...)
    -- Start a new shell and let it configure the path, environment, and whatnot from scratch, since
    -- the path depends on whether the active terminal supports color, and that may be different
    -- between a direct session and an rsh session.
    os.run({
        -- Monkey-patch `settings.get` to disable startup scripts, since that can run startup files
        -- from disks, which we don't control.
        _G = setmetatable({
            settings = setmetatable({
                get = function(name, ...)
                    if name == "shell.allow_startup" or name == "shell.allow_disk_startup" then
                        return false
                    end
                    return settings.get(name, ...)
                end,
            }, { __index = settings }),
        }, { __index = _G }),
    }, "rom/programs/shell.lua", ...)
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

        -- Even if `op_queue` is empty, send a message unconditionally as ping.
        rednet.send(client_id, {
            type = "term",
            session = params.session,
            ops = op_queue,
        }, "rsh")
        op_queue = {}

        if not out[1] or coroutine.status(coro) == "dead" then
            break
        end
        local filter = out[2]
        repeat
            event = table.pack(event_queue.get())
            -- The client adds dimension information to `term_resize` -- read it and make sure to
            -- remove it for consistency with base CraftOS.
            if event[1] == "term_resize" then
                size_x, size_y = event[2], event[3]
                event = { "term_resize" }
            end
        until event[1] == filter or filter == nil or event[1] == "terminate"
    end

    rednet.send(client_id, {
        type = "close",
        session = params.session,
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

async.drive()
