local async = require "../async"

local ui = {}

ui.ctrl_pressed = false
async.subscribe("key", function(key_code)
    if key_code == keys.leftCtrl or key_code == keys.rightCtrl then
        ui.ctrl_pressed = true
    end
end)
async.subscribe("key_up", function(key_code)
    if key_code == keys.leftCtrl or key_code == keys.rightCtrl then
        ui.ctrl_pressed = false
    end
end)

ui.TextField = {}
ui.TextField.__index = ui.TextField

function ui.TextField:new()
    return setmetatable({
        value = "",
        position = 1,
    }, self)
end

function ui.TextField:clear()
    self.value = ""
    self.position = 1
end

function ui.TextField:onKey(key_code)
    if key_code == keys.backspace or key_code == keys.capsLock then -- capslock for Colemak
        if self.position > 1 then
            if ui.ctrl_pressed then
                self.value = self.value:sub(self.position)
                self.position = 1
            else
                self.value = self.value:sub(1, self.position - 2) .. self.value:sub(self.position)
                self.position = self.position - 1
            end
            return true
        end
    elseif key_code == keys.delete then
        if self.position <= #self.value then
            self.value = self.value:sub(1, self.position - 1) .. self.value:sub(self.position + 1)
            return true
        end
    elseif ui.ctrl_pressed and key_code == keys.d then -- clear
        if self.value ~= "" then
            self.value = ""
            self.position = 1
            return true
        end
    elseif key_code == keys.right then
        if self.position <= #self.value then
            self.position = self.position + 1
            return true
        end
    elseif key_code == keys.left then
        if self.position > 1 then
            self.position = self.position - 1
            return true
        end
    elseif key_code == keys.home then
        self.position = 1
        return true
    elseif key_code == keys["end"] then
        self.position = #self.value + 1
        return true
    end
    return false
end

function ui.TextField:onChar(ch)
    if not ui.ctrl_pressed then
        self.value = self.value:sub(1, self.position - 1) .. ch .. self.value:sub(self.position)
        self.position = self.position + 1
        return true
    end
    return false
end

return ui
