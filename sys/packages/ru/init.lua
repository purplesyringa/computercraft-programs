local ru = {
    text = {},
    koi = {},
}

function ru.text.to_koi_char(ch)
    if ch >= 0x40 and ch < 0x80 then
        if ch >= 0x60 then
            ch = ch - 0x20
        else
            ch = ch + 0x20
        end
        ch = ch + 0x80
    end
    return ch
end

function ru.text.to_koi(s)
    s = { string.byte(s, 1, #s) }
    local raw = true
    local n = 0
    for i, ch in ipairs(s) do
        skip = false
        if raw and ch == 0x3C then
            raw, skip = false, true
        elseif not raw and ch == 0x3E then
            raw, skip = true, true
        end

        if not skip then
            n = n + 1

            if not raw then
                ch = ru.text.to_koi_char(ch)
            end
            s[n] = ch
        end
    end
    return string.char(table.unpack(s, 1, n))
end

local off = { 30, 0, 1, 22, 4, 5, 20, 3, 21, 8, 9, 10, 11, 12, 13, 14, 15, 31, 16, 17, 18, 19, 6, 2, 28, 27, 7, 24, 29, 25, 23, 26 }
function ru.koi.to_utf_char(ch)
    if ch >= 0xE0 then
        ch = 0x0430 + off[ch - 0xE0 + 1]
    elseif ch > 0xC0 then
        ch = 0x0410 + off[ch - 0xC0 + 1]
    elseif ch == 0xA3 then
        ch = 0x0451
    elseif ch == 0xB3 then
        ch = 0x0401
    end
    return ch
end

function ru.koi.to_utf(s)
    s = { string.byte(s, 1, #s) }
    for i, ch in ipairs(s) do
        s[i] = ru.koi.to_utf_char(ch)
    end
    return utf8.char(table.unpack(s))
end

function ru.text.to_utf(s)
    return ru.koi.to_utf(ru.text.to_koi(s))
end

return ru
