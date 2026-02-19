local remote_events = require("events").remote_events

local last_timer = nil
local TIMEOUT = 5

local function connect(server_id, ...)
    term.setCursorBlink(true)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    for i = 0, 15 do
        local index = bit.blshift(1, i)
        term.setPaletteColor(index, term.nativePaletteColor(index))
    end

    local session_id = math.random(1, 2147483647)
    rednet.send(server_id, {
        type = "open",
        session = session_id,
        cursor_pos = { term.getCursorPos() },
        size = { term.getSize() },
        is_color = term.isColor(),
        command = { ... },
    }, "rsh")

    local shift_down = false

    while true do
        local event = table.pack(os.pullEventRaw())

        -- Track Shift+Terminate.
        local function isShift(key)
            return key == keys.leftShift or key == keys.rightShift
        end
        if event[1] == "key" and isShift(event[2]) then
            shift_down = true
        elseif event[1] == "key_up" and isShift(event[2]) then
            shift_down = false
        end

        if event[1] == "terminate" and shift_down then
            rednet.send(server_id, { type = "kill", session = session_id }, "rsh")
            printError("Killed")
            break
        elseif remote_events[event[1]] then
            if event[1] == "term_resize" then
                -- Temporarily add size information to the event so that we can update the return
                -- value of `term.getSize` on the server.
                event = { "term_resize", term.getSize() }
            end
            rednet.send(server_id, { type = "event", session = session_id, event = event }, "rsh")
            if last_timer ~= nil then
                os.cancelTimer(last_timer)
            end
            last_timer = os.startTimer(TIMEOUT)
        elseif event[1] == "timer" and event[2] == last_timer then
            rednet.send(server_id, { type = "kill", session = session_id }, "rsh")
            printError("Timed out")
            break
        elseif event[1] == "rednet_message" then
            local _, sender_id, msg, protocol = table.unpack(event)
            if sender_id == server_id and protocol == "rsh" and msg.session == session_id then
                if msg.type == "term" then
                    for _, op in ipairs(msg.ops) do
                        term[op[1]](table.unpack(op, 2, op.n))
                    end
                elseif msg.type == "ack" and last_timer ~= nil then
                    os.cancelTimer(last_timer)
                    last_timer = nil
                elseif msg.type == "close" then
                    if msg.reason == "shutdown" then
                        printError("Server is shutting down")
                    elseif msg.reason == "reboot" then
                        printError("Server is rebooting")
                    elseif msg.reason == "terminate" then
                        printError("Server is terminated")
                    end
                    break
                elseif msg.type == "server_reset" then
                    printError("Connection reset")
                    break
                end
            end
        end
    end
end

local args = { ... }

if #args == 0 then
    print("Usage: rsh/client <hostname> [<command> <args...>]")
else
    local hostname = args[1]

    if multishell then
        multishell.setTitle(multishell.getCurrent(), "rsh " .. hostname)
    end

    peripheral.find("modem", rednet.open)
    local server_id = rednet.lookup("rsh", hostname)
    if server_id == nil then
        print("No host named", hostname)
    else
        connect(server_id, table.unpack(args, 2))
    end
end
