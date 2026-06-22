return function(key_to_char)
    local layout = {
        on_key = function(send_event, keys_pressed, event)
            local key = event[2]
            local per_level = key_to_char[keys.getName(key)]
            if per_level then
                local lv2 = keys_pressed[keys.leftShift] or keys_pressed[keys.rightShift]
                local lv3 = keys_pressed[keys.rightAlt]
                local char = (
                    (lv3 and lv2 and per_level[4])
                    or (lv3 and per_level[3])
                    or (lv2 and per_level[2])
                    or per_level[1]
                )
                if char then
                    send_event({ "char", char })
                    return true
                end
            end
        end,
    }
    return function()
        return layout
    end
end
