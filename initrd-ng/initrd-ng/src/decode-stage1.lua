local compressed = __DATA__
local trees = __TREES__

local tree_parsers = {}
for tree in trees:gmatch("[^\xff]+") do
    local len_buckets = {}
    local c = 0
    for i = 1, #tree do
        local byte = tree:byte(i)
        len_buckets[byte % 32] = len_buckets[byte % 32] or {}
        for i = -1, byte, 32 do
            table.insert(len_buckets[byte % 32], c)
            c = c + 1
        end
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
    table.insert(tree_parsers, __TREE1__ .. parsers[1] .. __TREE2__)
end

local s = load(__DECOMPRESS1__ .. table.concat(tree_parsers) .. __DECOMPRESS2__)(compressed)
return load(s, "=initrd", nil, _ENV)()
