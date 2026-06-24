local compressed = __DATA__
local tree = __TREE__

local function genCode(node, known, known_len)
    if type(node) == "number" then
        return ("__SYMBOL__=%d __BIT_POS__=__BIT_POS__+%d"):format(node, known_len)
    else
        local l, r = node[1], node[2]
        local boundary = known + bit32.lshift(1, 31 - known_len)
        return ("if __BITS__<%d then %s else %s end"):format(boundary, genCode(l, known, known_len + 1), genCode(r, boundary, known_len + 1))
    end
end

local s = load(__DECOMPRESS1__ .. genCode(tree, 0, 0) .. __DECOMPRESS2__)(compressed)
return load(s, "=initrd", nil, _ENV)()
