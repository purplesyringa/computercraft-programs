local redirect = require "redirect"
local svc = require "svc"

local args = { ... }
if #args < 2 then
    print("Usage: getty <monitor-name>/<keyboard-name> <command...>")
    print("Use 'default' as the peripheral name to use the built-in monitor/keyboard.")
    return
end
local seat_def = args[1]
local command = { table.unpack(args, 2) }

if seat_def == "default" then
    seat_def = "default/default"
end
local monitor_name, keyboard_name = seat_def:match("^([^/]+)/([^/]+)$")
assert(monitor_name, "Invalid seat definition '" .. seat_def .. "'")

local monitor
if monitor_name == "default" then
    monitor = term.native()
else
    monitor = peripheral.wrap(monitor_name)
    assert(monitor, "No monitor named '" .. monitor_name .. "'")
end

local function matchesMonitor(name)
    return (name or "default") == monitor_name
end

local function matchesKeyboard(name)
    return (name or "default") == keyboard_name
end

local bg_command = redirect.runWithEventSource(redirect.runWithTerm, monitor, function()
    local nested_shell = svc.makeNestedShell({ shell = shell })
    svc.reloadShellEnv(nested_shell)
    nested_shell.execute(table.unpack(command))
end)

local shift_pressed = false
local event

local function deliver()
    bg_command.pushEvent(table.unpack(event, 1, event.n))
end

while not bg_command.isDead() do
    event = table.pack(os.pullEventRaw())

    -- Events originating from keyboard are delivered only when arriving from the expected
    -- keyboard. Events originating from monitor have different IDs from the default terminal
    -- events, so the confusion doesn't arise and we can deliver both the original event and the
    -- rewritten event.
    if event[1] == "char" or event[1] == "paste" then
        if matchesKeyboard(event[3]) then
            deliver()
        end
    elseif event[1] == "key" then
        if matchesKeyboard(event[4]) then
            if event[2] == keys.leftShift or event[2] == keys.rightShift then
                shift_pressed = true
            end
            deliver()
        end
    elseif event[1] == "key_up" then
        if matchesKeyboard(event[3]) then
            if event[2] == keys.leftShift or event[2] == keys.rightShift then
                shift_pressed = false
            end
            deliver()
        end
    elseif event[1] == "monitor_resize" then
        if matchesMonitor(event[2]) then
            bg_command.pushEvent("term_resize")
        end
        deliver()
    elseif event[1] == "term_resize" then
        if matchesMonitor(nil) then
            deliver()
        end
    elseif event[1] == "monitor_touch" then
        if matchesMonitor(event[2]) then
            local button = 1
            if shift_pressed then
                button = 2
            end
            bg_command.pushEvent("mouse_click", button, event[3], event[4])
            bg_command.pushEvent("mouse_up", button, event[3], event[4])
        end
        deliver()
    elseif (
        event[1] == "mouse_click"
        or event[1] == "mouse_drag"
        or event[1] == "mouse_scroll"
        or event[1] == "mouse_up"
    ) then
        if matchesMonitor(nil) then
            deliver()
        end
    elseif event[1] == "terminate" then
        -- e.g. hangup
        deliver()
    elseif event[1] == "fg_terminate" then
        if matchesMonitor(event[2]) then
            bg_command.pushEvent("terminate")
        end
    else
        deliver()
    end
end
