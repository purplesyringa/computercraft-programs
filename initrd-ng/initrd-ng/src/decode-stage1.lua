local compressed = __DATA__
local trees = __TREES__

local parsed_trees = {}
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
            table.insert(parsers, ("return %d,%d"):format(c, bit_len))
        end
        local new_parsers = {}
        for i = 1, #parsers, 2 do
            table.insert(
                new_parsers,
                ("if ...<%d then %s else %s end"):format(
                    i * 2 ^ (32 - bit_len),
                    parsers[i],
                    parsers[i + 1]
                )
            )
        end
        parsers = new_parsers
    end
    table.insert(parsed_trees, load(parsers[1]))
end

local s = load(__DECOMPRESS__)(compressed, parsed_trees)
return load(s, "=initrd", nil, _ENV)()
