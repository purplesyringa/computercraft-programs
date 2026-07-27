local environ = require "environ"
local expect = require "cc.expect".expect
local Seat = require "getty.seat"
local keyboard = require "keyboard"
local redirect = require "redirect"

local Controller = {}

function Controller.new(name)
    expect(1, name, "string")
    local self = setmetatable({
        seat = Seat.new(name),
        running = false,
        deliver = nil,
        keyboard = nil,
    }, { __index = Controller })

    self.keyboard_event_name = self.seat.names.keyboard
    if not self.seat.names.keyboard then
        self.keyboard_event_name = "" -- a sentinel name no keyboard can have
    elseif self.seat.names.keyboard == "default" then
        self.keyboard_event_name = nil -- the built-in keyboard sends events without the keyboard field
    end

    return self
end

function Controller:run(...)
    assert(not self.running, "can't run commands while a command is running!")
    self.running = true

    self.seat:reset()
    self.seat.monitor.setCursorPos(1, 1)
    self.seat.monitor.clear()

    local bg_command = redirect.runWithEventSource(
        redirect.runWithTerm, self.seat.monitor, self.seat,
        environ.exec, { base_shell = shell, reload = true }, ...
    )

    function self.deliver(event)
        bg_command.pushEvent(table.unpack(event, 1, event.n))
    end

    self.keyboard = keyboard.new(self.deliver)

    while not bg_command.isDead() do
        self:_processEvent(table.pack(os.pullEventRaw()))
    end

    self.running = false
end

function Controller:_processEvent(event)
    -- Events originating from keyboard are delivered only when arriving from the expected keyboard.
    -- Events originating from monitor have different IDs from the default terminal events, so the
    -- confusion doesn't arise and we can deliver both the original event and the rewritten event.
    if event[1] == "char" then
        if self.keyboard_event_name == event[3] then
            self.keyboard:on_char(event)
        end
    elseif event[1] == "paste" then
        if self.keyboard_event_name == event[3] then
            self.deliver(event)
        end
    elseif event[1] == "key" then
        if self.keyboard_event_name == event[4] then
            self.keyboard:on_key(event)
        end
    elseif event[1] == "key_up" then
        if self.keyboard_event_name == event[3] then
            self.keyboard:on_key_up(event)
        end
    elseif event[1] == "monitor_resize" then
        if self.seat.names.monitor == event[2] then
            self.deliver({ "term_resize" })
        end
        self.deliver(event)
    elseif event[1] == "term_resize" then
        if self.seat.names.monitor == "default" then
            self.deliver(event)
        end
    elseif event[1] == "monitor_touch" then
        if self.seat.names.monitor == event[2] then
            local button = 1
            if keyboard.keys_pressed[keys.leftShift] or keyboard.keys_pressed[keys.rightShift] then
                button = 2
            end
            self.deliver({ "mouse_click", button, event[3], event[4] })
            self.deliver({ "mouse_up", button, event[3], event[4] })
        end
        self.deliver(event)
    elseif (
        event[1] == "mouse_click"
        or event[1] == "mouse_drag"
        or event[1] == "mouse_scroll"
        or event[1] == "mouse_up"
    ) then
        if self.seat.names.monitor == "default" then
            self.deliver(event)
        end
    elseif event[1] == "terminate" then
        -- e.g. hangup
        self.deliver(event)
    elseif event[1] == "fg_terminate" then
        if self.keyboard_event_name == event[2] then
            self.deliver({ "terminate" })
        end
    else
        self.deliver(event)
    end
end

return Controller
