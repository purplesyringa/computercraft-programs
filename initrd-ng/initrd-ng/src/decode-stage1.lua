local booted, compressed, tables, cache, table_parsers = os.clock(), __DATA__, __TABLES__, __CACHE__, {}
for tbl in tables:gmatch("[^\xff]+") do
    local parsers, sum, c = {}, 0, 0 -- each parser is a tuple { level, cumulative, code }
    for _, p in utf8.codes(tbl) do
        if p > 0 and p < 0x2000 then
            -- Build a binary tree, using probabilities as weights. This uses a stack-based
            -- algorithm, storing nodes roughly like in a segment tree. For each node, we detect
            -- which level of the tree we're ready to finish and merge all parsers up to the
            -- previous parser of a higher level. Technically, the true level is the ctz of the xor,
            -- but just using the xor works as well, since we never have to compare nodes of two
            -- equal levels.
            local level, cumulative, code =
                bit32.bxor(sum, sum + p),
                sum,
                -- Mathematically, this can be optimized to `state * c1 + bits * c2 - sum`, saving
                -- a local access, but it's unclear if it's still safe under IEEE-754 rounding. We
                -- have previously refrained from this optimization when we had 53 state bits and 14
                -- probability bits, as it caused issues with empirical probability 2^-28. We now
                -- have 51 state bits and 13 probability bits, so this might no longer apply, but we
                -- don't have a proof of that.
                ("__SYMBOL__=%d __STATE__=(__STATE__-__BITS__)*%q+__BITS__-%d"):format(c, p / 2 ^ 13, sum)
            while #parsers > 0 and parsers[#parsers][1] < level do
                local old_parser = table.remove(parsers)
                code = ("if __BITS__<%d then %s else %s end"):format(
                    cumulative,
                    old_parser[3],
                    code
                )
                cumulative = old_parser[2]
            end
            table.insert(parsers, { level, cumulative, code })
            sum = sum + p
        end
        c = c + math.max(1, p - 0x2000)
    end
    table.insert(table_parsers, __TABLE1__ .. parsers[1][3] .. __TABLE2__)
end

local s = load(__DECOMPRESS1__ .. table.concat(table_parsers) .. __DECOMPRESS2__)(compressed, cache)
return load(s, "=initrd", nil, _ENV)(booted)
