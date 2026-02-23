import re
from .minify import minify
from .ser import serialize

decompress_mtf = minify("""
    local compressed = ...

    local repetitions = {}
    for c = 0, 255 do
        repetitions[c] = { c, n = 1 }
    end

    local byte_cache = {}
    for c = 0, 255 do
        byte_cache[c + 1] = c
    end
    local rle = 1
    local bwt = {}
    local bwt_pos = 1
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
                local count = rle - 1
                local r = repetitions[byte_cache[1]]
                while r.n < count do
                    table.move(r, 1, r.n, r.n + 1)
                    r.n = r.n * 2
                end
                table.move(r, 1, count, bwt_pos, bwt)
                bwt_pos = bwt_pos + count
                rle = 1
            end
            local byte = byte_cache[symbol]
            table.move(byte_cache, 1, symbol - 1, 2)
            byte_cache[1] = byte
            bwt[bwt_pos] = byte
            bwt_pos = bwt_pos + 1
        end
    end
    bwt[bwt_pos - 1] = nil
    return bwt
""")

bits = re.search(r"local (\w+)=bit32.lshift", decompress_mtf)[1]
symbol = re.search(r"if (\w+)<2", decompress_mtf)[1]
bit_pos = re.search(r"local (\w+)=8", decompress_mtf)[1]
decompress_mtf1, decompress_mtf2 = decompress_mtf.split("DECODE_SYMBOL()")
decompress_mtf2 = " " + decompress_mtf2 # for concatenation with generated code

code_template = minify("""
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

    local bwt = load(DECOMPRESS_MTF1 .. genCode(tree, 0, 0) .. DECOMPRESS_MTF2)(compressed)

    local counts = {}
    for c = -1, 255 do
        counts[c] = 0
    end
    local pos_in_char = { [#bwt] = 0 }
    for i, c in ipairs(bwt) do
        local new_count = counts[c] + 1
        counts[c] = new_count
        pos_in_char[i] = new_count
    end
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
    s = string.char(table.unpack(s))

    return load(s, "initrd", nil, _ENV)()
""")

code_template = (
    code_template
        .replace("SYMBOL", symbol)
        .replace("BIT_POS", bit_pos)
        .replace("BITS", bits)
        .encode()
        .replace(b"DECOMPRESS_MTF1", serialize(decompress_mtf1))
        .replace(b"DECOMPRESS_MTF2", serialize(decompress_mtf2))
)

def generate_sfx(data: bytes, tree: object, total_bit_len: int, shift: int) -> bytes:
    return (
        code_template
            .replace(b"DATA", serialize(data))
            .replace(b"TREE", serialize(tree))
            .replace(b"LIMIT", str(8 + total_bit_len).encode())
            .replace(b"SHIFT", str(shift + 1).encode())
    )
