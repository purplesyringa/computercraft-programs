local function newTerminalRedirect(handlers)
    local redirect = {}

    local function handling(name, pre)
        return function(...)
            if pre ~= nil then
                pre(...)
            end
            handlers[name](...)
        end
    end

    -- Constants.
    redirect.isColour = handlers.isColor
    redirect.isColor = handlers.isColor
    redirect.getSize = handlers.getSize

    -- Properties we have to keep track of because the Redirect interface forces us to provide
    -- getters.
    local cursor_x, cursor_y = 1, 1
    redirect.getCursorPos = function() return cursor_x, cursor_y end
    redirect.setCursorPos = handling("setCursorPos", function(x, y) cursor_x, cursor_y = x, y end)

    local cursor_blink = true
    redirect.getCursorBlink = function() return cursor_blink end
    redirect.setCursorBlink = handling("setCursorBlink", function(blink) cursor_blink = blink end)

    local text_color = colors.white
    redirect.getTextColor = function() return text_color end
    redirect.getTextColour = redirect.getTextColor
    redirect.setTextColor = handling("setTextColor", function(color) text_color = color end)
    redirect.setTextColor = redirect.setTextColour

    local background_color = colors.black
    redirect.getBackgroundColor = function() return background_color end
    redirect.getBackgroundColour = redirect.getBackgroundColor
    redirect.setBackgroundColor = handling("setBackgroundColor", function(color)
        background_color = color
    end)
    redirect.setBackgroundColour = redirect.setBackgroundColor

    local palette = {}
    for i = 0, 15 do
        local index = bit.blshift(1, i)
        palette[index] = { term.nativePaletteColor(index) }
    end
    redirect.getPaletteColor = function(color) return table.unpack(palette[color]) end
    redirect.getPaletteColour = redirect.getPaletteColor
    redirect.setPaletteColor = handling("setPaletteColor", function(color, ...)
        local params = table.pack(...)
        if params.n == 1 then
            palette[color] = colors.unpackRGB(rgb)
        else
            palette[color] = params
        end
    end)
    redirect.setPaletteColour = redirect.setPaletteColor

    -- Operations that don't mutate properties.
    redirect.clear = handling("clear")
    redirect.clearLine = handling("clearLine")
    redirect.scroll = handling("scroll")

    -- Operations that move the cursor.
    redirect.write = handling("write", function(text) cursor_x = cursor_x + #text end)
    redirect.blit = handling("blit", function(text) cursor_x = cursor_x + #text end)

    return redirect
end

return {
    newTerminalRedirect = newTerminalRedirect,
}
