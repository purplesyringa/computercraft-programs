local compressed = __DATA__
local bit_lengths = __TREE__

local len_buckets = {}
for i = 1, #bit_lengths do
    local bit_len = bit_lengths:byte(i)
    if not len_buckets[bit_len] then
        len_buckets[bit_len] = {}
    end
    table.insert(len_buckets[bit_len], i - 1)
end

local parsers = {}
for bit_len = 25, 1, -1 do
    for _, c in ipairs(len_buckets[bit_len] or {}) do
        table.insert(parsers, ("__SYMBOL__=%d __BIT_POS__=__BIT_POS__+%d"):format(c, bit_len))
    end
    local new_parsers = {}
    for i = 1, #parsers, 2 do
        table.insert(
            new_parsers,
            ("if __BITS__<%d then %s else %s end"):format(
                i * 2 ^ (32 - bit_len),
                parsers[i],
                parsers[i + 1]
            )
        )
    end
    parsers = new_parsers
end

local s = load(__DECOMPRESS1__ .. parsers[1] .. __DECOMPRESS2__)(compressed)
return load(s, "=initrd", nil, _ENV)()
