local async = require "async"
local util = require "util"
local ui = require "ui"

local common = {}

-- Add missing colors for Minecraft formatting codes to the palette at unused indices.
term.setPaletteColor(0x40, 0x992222) -- was pink, now dark red
term.setPaletteColor(0x1000, 0x82e0e0) -- was brown, now aqua
local mc_to_cc_colors = {
    ["0"] = 0x8000,
    ["1"] = 0x800,
    ["2"] = 0x2000,
    ["3"] = 0x200,
    ["4"] = 0x40,
    ["5"] = 0x400,
    ["6"] = 0x2,
    ["7"] = 0x100,
    ["8"] = 0x80,
    ["9"] = 0x8,
    ["a"] = 0x20,
    ["b"] = 0x1000,
    ["c"] = 0x4000,
    ["d"] = 0x4,
    ["e"] = 0x10,
    ["f"] = 0x1,
}

local search_field = ui.TextField:new()
local scroll_pos = 1
common.index = {} -- Type: { [key] = item, ... }
local fullness = 0 -- percentage
common.filtered_index = {} -- Type: { item, ... }, sorted by decreasing count

function common.hasSearchQuery()
    return search_field.value ~= ""
end

function common.getVisibleItem(position)
    return common.filtered_index[position + scroll_pos - 1]
end

function common.formatItemName(item)
    if item.name == "minecraft:enchanted_book" and next(item.enchantments or {}) then
        local enchantments = {}
        for _, enchantment in ipairs(item.enchantments) do
            table.insert(enchantments, enchantment.displayName)
        end
        return table.concat(enchantments, " + ")
    end

    -- Smithing templates don't export their name anywhere. Match by display name because mods add
    -- their own smithing templates without setting any recognizable tags. This assumes English
    -- locale, but that makes some sense because we can't print non-Latin characters anyway.
    if item.displayName == "Smithing Template" then
        local i = item.name:find(":")
        local name = item.name:sub(i + 1):gsub("_smithing_template$", "")
        local words = {}
        for word in name:gmatch("[^_]+") do
            table.insert(words, word:sub(1, 1):upper() .. word:sub(2))
        end
        return table.concat(words, " ")
    end

    return item.displayName
end

function common.formatItemCount(item)
    if item.maxCount < 64 or item.count < 320 then
        return string.format("%d", item.count)
    end
    local stacks = math.floor(item.count / item.maxCount)
    local remainder = item.count % item.maxCount
    if remainder == 0 or stacks >= 100 then
        return string.format("%ds", stacks)
    else
        return string.format("%ds %d", stacks, remainder)
    end
end

local SECTION_SIGN = "\xa7"

local function parseFormattedText(text)
    local out = {}
    local color = nil
    local i = 1
    while true do
        local next_formatting_code = text:find(SECTION_SIGN, i)
        if next_formatting_code == nil then
            break
        end
        table.insert(out, {
            color = color,
            text = text:sub(i, next_formatting_code - 1),
        })
        local ch = text:sub(next_formatting_code + 1, next_formatting_code + 1)
        if mc_to_cc_colors[ch] then
            color = mc_to_cc_colors[ch]
        elseif ch == "r" then
            color = nil
        end
        i = next_formatting_code + 2
    end
    table.insert(out, {
        color = color,
        text = text:sub(i),
    })
    return out
end

local function stripFormatting(text)
    return text:gsub(SECTION_SIGN .. ".", "")
end

local function itemMatchesQuery(item, query)
    if query == "" then
        return true
    end

    if query:sub(1, 1) == "@" then
        local i = item.name:find(":")
        local mod_name = item.name:sub(1, i - 1)
        local mod_query = query:sub(2)
        return util.stringContainsCaseInsensitive(mod_name, mod_query)
    end

    if query:sub(1, 1) == "#" then
        local tag_query = query:sub(2)
        for tag, _ in pairs(item.tags) do
            if util.stringContainsCaseInsensitive(tag, tag_query) then
                return true
            end
        end
        return false
    end

    local function checkNameOrDisplayName(obj)
        return (
            util.stringContainsCaseInsensitive(obj.name, query)
            or util.stringContainsCaseInsensitive(stripFormatting(obj.displayName), query)
        )
    end

    if checkNameOrDisplayName(item) then
        return true
    end
    -- Some items, like smithing templates, are formatted into a name that is not present as
    -- a substring in data. Recognize that.
    if util.stringContainsCaseInsensitive(
        stripFormatting(common.formatItemName(item)),
        query
    ) then
        return true
    end
    for _, lore in pairs(item.lore or {}) do
        if util.stringContainsCaseInsensitive(stripFormatting(lore), query) then
            return true
        end
    end
    for _, enchantment in pairs(item.enchantments or {}) do
        if checkNameOrDisplayName(enchantment) then
            return true
        end
    end
    for _, effect in pairs(item.potionEffects or {}) do
        if checkNameOrDisplayName(effect) then
            return true
        end
    end
    return false
end

local function updateFilteredIndex()
    common.filtered_index = {}
    for _, item in pairs(common.index) do
        if item.count > 0 and itemMatchesQuery(item, search_field.value) then
            table.insert(common.filtered_index, item)
        end
    end
    table.sort(common.filtered_index, function(a, b)
        if a.count == b.count then
            return util.getItemKey(a) < util.getItemKey(b)
        end
        return a.count > b.count
    end)
end

function common.reset()
    search_field:clear()
    scroll_pos = 1
    updateFilteredIndex()
end

function common.writeFormattedText(text, default_color)
    for _, chunk in pairs(parseFormattedText(text)) do
        term.setTextColor(chunk.color or default_color)
        term.write(chunk.text)
    end
end

function common.renderSearchBar()
    term.setCursorPos(8, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(search_field.value)

    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.yellow)
    term.setTextColor(colors.black)
    term.write(string.format("%5d%%", fullness))

    term.setTextColor(colors.white)
    term.setCursorPos(7 + search_field.position, 1)
    term.setCursorBlink(true)
end

function common.renderIndex(first_row, last_row, highlighted_keys)
    scroll_pos = math.max(1, math.min(scroll_pos, first_row + #common.filtered_index - last_row))

    for y = first_row, last_row do
        local item = common.filtered_index[scroll_pos + y - first_row]
        if item then
            term.setCursorPos(8, y)
            term.setBackgroundColor(colors.black)
            local default_color = colors.white
            if highlighted_keys[util.getItemKey(item)] then
                default_color = colors.green
            end
            common.writeFormattedText(common.formatItemName(item), default_color)
        end
        term.setCursorPos(1, y)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        if item then
            local count = string.format("%6s", common.formatItemCount(item))
            local pos_s = count:find("s")
            if pos_s == nil then
                term.write(count)
            else
                term.write(count:sub(1, pos_s - 1))
                term.setTextColor(colors.lightBlue)
                term.write("s")
                term.setTextColor(colors.white)
                term.write(count:sub(pos_s + 1))
            end
        else
            term.write("      ")
        end
    end
end

function common.onKey(key_code, page_height)
    local old_search_query = search_field.value
    if search_field:onKey(key_code) then
        if search_field.value ~= old_search_query then
            updateFilteredIndex()
            return "search"
        end
        return "gui"
    elseif key_code == keys.up then
        scroll_pos = scroll_pos - 1
        return "gui"
    elseif key_code == keys.down then
        scroll_pos = scroll_pos + 1
        return "gui"
    elseif key_code == keys.pageUp then
        scroll_pos = scroll_pos - page_height
        return "gui"
    elseif key_code == keys.pageDown then
        scroll_pos = scroll_pos + page_height
        return "gui"
    end
    return nil
end

function common.onChar(ch)
    if search_field:onChar(ch) then
        updateFilteredIndex()
        return "search"
    end
    return nil
end

function common.onMouseScroll(direction)
    scroll_pos = scroll_pos + direction * 3
end

function common.loadInventory()
    return async.parMap(util.iota(16), function(slot)
        return turtle.getItemDetail(slot, true)
    end)
end

function common.patchIndex(msg)
    if msg.reset then
        common.index = {}
    end
    for key, item in pairs(msg.items) do
        common.index[key] = item
    end
    fullness = msg.fullness
    updateFilteredIndex()
end

-- Returns `nil, nil` if the rail doesn't have a minecart.
function common.wrapRailWired(side)
    -- We can only move items between ourselves and the rail over wired network, since we can't name
    -- ourselves for the rail, and the wired name doesn't work outside wired networks. We're
    -- connected to the rail directly and we know there is a cart there, so we can use its UUID to
    -- find a matching rail on the wired network.
    local direct_rail = peripheral.wrap(side)
    assert(direct_rail, "No rail")

    local wired_rails = {
        peripheral.find("minecraft:powered_rail", function(name)
            return name ~= side
        end)
    }

    local carts = async.gather({
        direct_rail = direct_rail.getMinecarts,
        wired_rails = function()
            return async.parMap(wired_rails, function(rail)
                return rail.getMinecarts()
            end)
        end,
    })
    if not next(carts.direct_rail) then
        return nil, nil
    end
    assert(#carts.direct_rail == 1, "multiple minecarts on the rail")
    local cart = carts.direct_rail[1]

    for key, wired_carts in pairs(carts.wired_rails) do
        if #wired_carts == 1 and wired_carts[1].uuid == cart.uuid then
            return wired_rails[key], cart
        end
    end
    error("rail not connected to wired network")
end

function common.sendCartToPortal(rail)
    -- Push the cart in both directions at once. Since the cart is close to the turtle, it can speed
    -- up in the direction of the portal much more than in the opposite one, so this reliably sends
    -- the cart to the overworld.
    rail.pushMinecarts(false)
    rail.pushMinecarts(true)
end

return common
