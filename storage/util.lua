local util = {}

function util.iota(n)
    local out = {}
    for i = 1, n do
        table.insert(out, i)
    end
    return out
end

function util.map(tbl, callback)
    local out = {}
    for key, value in pairs(tbl) do
        out[key] = callback(value, key)
    end
    return out
end

function util.retain(tbl, callback)
    local j = 1
    for i = 1, #tbl do
        if callback(tbl[i], i) then
            tbl[j] = tbl[i]
            j = j + 1
        end
    end
    for i = j, #tbl do
        tbl[i] = nil
    end
end

function util.bind(f, ...)
    local args1 = table.pack(...)
    return function(...)
        local args1_copy = table.pack(table.unpack(args1, 1, args1.n))
        local args2 = table.pack(...)
        local args = table.move(args2, 1, args2.n, args1.n + 1, args1_copy)
        return f(table.unpack(args))
    end
end

function util.getItemKey(item)
    if item then
        return string.format("%s %s %s", item.name, item.nbt, item.damage)
    else
        return "empty"
    end
end

function util.itemWithCount(item, count)
    local new_item = {}
    for k, v in pairs(item) do
        new_item[k] = v
    end
    new_item.count = count
    return new_item
end

function util.stringContainsCaseInsensitive(haystack, needle)
    return string.find(haystack:lower(), needle:lower(), nil, true) ~= nil
end

return util
