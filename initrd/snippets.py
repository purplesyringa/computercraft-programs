import re
from .minify import minify
from .ser import serialize

decompress = minify("decompress", """
    local compressed = ...

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

    while bit_pos < LIMIT do
        local bits = bit32.lshift(
            string.unpack(">I", compressed, bit32.rshift(bit_pos, 3)),
            bit_pos % 8
        )
        DECODE_SYMBOL()
        if symbol < 2 then
            rle = rle * 2 + symbol
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
    local s = { [#bwt] = 0 }
    local pos = SHIFT
    for i = 1, #bwt do
        local c = bwt[pos]
        s[i] = c
        pos = pos_in_char[pos] + counts[c]
    end
    return string.char(table.unpack(s))
""")

bits = re.search(r"local (\w+)=bit32.lshift", decompress)[1]
symbol = re.search(r"if (\w+)<2", decompress)[1]
bit_pos = re.search(r"local (\w+)=8", decompress)[1]
decompress1, decompress2 = decompress.split("DECODE_SYMBOL()")
decompress2 = " " + decompress2 # for concatenation with generated code

code_template = minify("code_template", """
    local compressed = DATA
    local tree = TREE

    local function genCode(node, known, known_len)
        if type(node) == "number" then
            return ("SYMBOL=%d BIT_POS=BIT_POS+%d"):format(node, known_len)
        else
            local l, r = node[1], node[2]
            local boundary = known + bit32.lshift(1, 31 - known_len)
            return ("if BITS<%d then %s else %s end"):format(boundary, genCode(l, known, known_len + 1), genCode(r, boundary, known_len + 1))
        end
    end

    local s = load(DECOMPRESS1 .. genCode(tree, 0, 0) .. DECOMPRESS2)(compressed)
    return load(s, "initrd", nil, _ENV)()
""")

code_template = (
    code_template
        .replace("SYMBOL", symbol)
        .replace("BIT_POS", bit_pos)
        .replace("BITS", bits)
        .encode()
        .replace(b"DECOMPRESS1", serialize(decompress1))
        .replace(b"DECOMPRESS2", serialize(decompress2))
)

def generate_sfx(data: bytes, tree: object, total_bit_len: int, shift: int) -> bytes:
    return (
        code_template
            .replace(b"DATA", serialize(data))
            .replace(b"TREE", serialize(tree))
            .replace(b"LIMIT", str(8 + total_bit_len).encode())
            .replace(b"SHIFT", str(shift + 1).encode())
    )
