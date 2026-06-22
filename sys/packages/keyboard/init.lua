-- Stateless native layout.
local native_layout = {
    on_key = function() end,
}

local Handler = {}

function Handler.new(send_event)
    local kb = setmetatable({
        native_layout = native_layout,
        layouts = {},
        keys_pressed = {},
        recent_layout_change = false,
        allow_next_char = false,
        suppress_next_char = true,
        send_event = send_event,
    }, { __index = Handler })
    kb:setNativeLayout()
    return kb
end

function Handler:setNativeLayout()
    self.active_layout = self.native_layout
end

function Handler:toggleLayout()
    if self.active_layout == native_layout then
        if self.last_custom_layout_name then
            self:setCustomLayout(self.last_custom_layout_name)
        end
    else
        self:setNativeLayout()
    end
end

function Handler:setCustomLayout(key)
    local next_layout = self.layouts[key]
    if next_layout then
        self.last_custom_layout_name = key
        self.active_layout = next_layout()
    end
end

function Handler:on_key(event)
    self.send_event(event)
    self.allow_next_char = false
    if self.keys_pressed[keys.leftAlt] and self.keys_pressed[keys.leftShift] then
        -- Ignore repetitions.
        if not event[3] then
            self:setCustomLayout(event[2])
            self.recent_layout_change = true
        end
        -- Don't mark the key as pressed so that `on_key_up` is not called for it,
        -- since from the perspective of the layout it's never been pressed.
    elseif not event[3] or self.keys_pressed[event[2]] then
        self.suppress_next_char = self.active_layout.on_key(self.send_event, self.keys_pressed, event)
        self.keys_pressed[event[2]] = true
        self.allow_next_char = true
    end
end

function Handler:on_key_up(event)
    self.send_event(event)
    if self.keys_pressed[keys.leftAlt] and self.keys_pressed[keys.leftShift]
        and (event[2] == keys.leftAlt or event[2] == keys.leftShift)
    then
        if self.recent_layout_change then
            self.recent_layout_change = false
        else
            self:toggleLayout()
        end
    end
    if self.keys_pressed[event[2]] then
        if self.active_layout.on_key_up then
            self.active_layout.on_key_up(self.send_event, self.keys_pressed, event)
        end
    end
    self.keys_pressed[event[2]] = nil
end

function Handler:on_char(event)
    if self.allow_next_char then
        if not self.suppress_next_char then
            self.send_event(event)
        end
        if self.active_layout.on_char then
            self.active_layout.on_char(self.send_event, self.keys_pressed, event)
        end
    end
end

return Handler
