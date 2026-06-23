local hardware = require "hardware"
local keyboard = require "keyboard"
local redirect = require "redirect"
local svc = require "svc"

local args = { ... }
if #args < 2 then
    print("Usage: getty <seat> <command...>")
    print("Use 'default' as the seat to use the built-in monitor and keyboard.")
    return
end

local seat = args[1]
local command = { table.unpack(args, 2) }

local names
if seat == "default" then
    names = { monitor = "default", keyboard = "default" }
else
    names = hardware.resolveGroup(seat)
end

assert(names.monitor, seat .. ".monitor is undefined")
local monitor
if names.monitor == "default" then
    monitor = term.native()
else
    monitor = peripheral.wrap(names.monitor)
    assert(monitor, "monitor " .. names.monitor .. " is not connected")
end

local keyboard_event_name = names.keyboard
if not names.keyboard then
    keyboard_event_name = "" -- a sentinel name no keyboard can have
elseif names.keyboard == "default" then
    keyboard_event_name = nil -- the built-in keyboard sends events without the keyboard field
end

local bg_command = redirect.runWithEventSource(redirect.runWithTerm, monitor, function()
    local nested_shell = svc.makeNestedShell({ shell = shell })
    svc.reloadShellEnv(nested_shell)
    nested_shell.execute(table.unpack(command))
end)

local function deliver(event)
    bg_command.pushEvent(table.unpack(event, 1, event.n))
end

local kb = keyboard.new(deliver)

while not bg_command.isDead() do
    local event = table.pack(os.pullEventRaw())

    -- Events originating from keyboard are delivered only when arriving from the expected
    -- keyboard. Events originating from monitor have different IDs from the default terminal
    -- events, so the confusion doesn't arise and we can deliver both the original event and the
    -- rewritten event.
    if event[1] == "char" then
        if keyboard_event_name == event[3] then
            kb:on_char(event)
        end
    elseif event[1] == "paste" then
        if keyboard_event_name == event[3] then
            deliver(event)
        end
    elseif event[1] == "key" then
        if keyboard_event_name == event[4] then
            kb:on_key(event)
        end
    elseif event[1] == "key_up" then
        if keyboard_event_name == event[3] then
            kb:on_key_up(event)
        end
    elseif event[1] == "monitor_resize" then
        if names.monitor == event[2] then
            bg_command.pushEvent("term_resize")
        end
        deliver(event)
    elseif event[1] == "term_resize" then
        if names.monitor == "default" then
            deliver(event)
        end
    elseif event[1] == "monitor_touch" then
        if names.monitor == event[2] then
            local button = 1
            if kb.keys_pressed[keys.leftShift] or kb.keys_pressed[keys.rightShift] then
                button = 2
            end
            bg_command.pushEvent("mouse_click", button, event[3], event[4])
            bg_command.pushEvent("mouse_up", button, event[3], event[4])
        end
        deliver(event)
    elseif (
        event[1] == "mouse_click"
        or event[1] == "mouse_drag"
        or event[1] == "mouse_scroll"
        or event[1] == "mouse_up"
    ) then
        if names.monitor == "default" then
            deliver(event)
        end
    elseif event[1] == "terminate" then
        -- e.g. hangup
        deliver(event)
    elseif event[1] == "fg_terminate" then
        if keyboard_event_name == event[2] then
            bg_command.pushEvent("terminate")
        end
    else
        deliver(event)
    end
end
