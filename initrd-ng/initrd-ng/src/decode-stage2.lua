local compressed, trees = ...

local byte_cache = {}
for c = 0, 255 do
    byte_cache[c + 1] = c
end

local rle = 1

local bwt = {}
local bwt_pos = 0
local counts = {}
for c = -1, 255 do
    counts[c] = 0
end
local pos_in_char = {}

local bit_pos = 8
local symbol
local bit_len
local tree = trees[1]

while bit_pos < __LIMIT__ do
    local bits = bit32.lshift(
        string.unpack(">I", compressed, bit32.rshift(bit_pos, 3)),
        bit_pos % 8
    )

    symbol, bit_len = tree(bits)
    bit_pos = bit_pos + bit_len

    if symbol < 2 then
        rle = rle * 2 + symbol
    elseif symbol > 256 then
        tree = trees[symbol - 256]
    else
        if rle > 1 then
            local byte = byte_cache[1]
            local count = rle - 1
            local last_count = counts[byte]
            for i = 1, count do
                bwt[bwt_pos + i] = byte
                pos_in_char[bwt_pos + i] = last_count + i
            end
            counts[byte] = last_count + count
            bwt_pos = bwt_pos + count
            rle = 1
        end
        bwt_pos = bwt_pos + 1
        local byte = byte_cache[symbol]
        table.move(byte_cache, 1, symbol - 1, 2)
        byte_cache[1] = byte
        bwt[bwt_pos] = byte
        local new_count = counts[byte] + 1
        counts[byte] = new_count
        pos_in_char[bwt_pos] = new_count
    end
end
counts[bwt[bwt_pos]] = counts[bwt[bwt_pos]] - 1
bwt[bwt_pos] = nil

for c = 1, 255 do
    counts[c] = counts[c] + counts[c - 1]
end
table.move(counts, -1, 254, 0)
local s = {}
local pos = __SHIFT__
for i = #bwt, 1, -1 do
    local c = bwt[pos]
    s[i] = c
    pos = pos_in_char[pos] + counts[c]
end
return string.char(table.unpack(s))
