local async = require "async"
local util = require "storage.util"
local ui = require "storage.ui"
local discs = require "storage.discs"

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

local function snakeCaseToTitleCase(s)
    local words = {}
    for word in s:gmatch("[^_]+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2))
    end
    return table.concat(words, " ")
end

local SECTION_SIGN = "\xa7"

local function stripFormatting(text)
    return text:gsub(SECTION_SIGN .. ".", "")
end

function common.formatItemName(item)
    -- Override display names of items whose default names are too vague to be useful. We only
    -- override the *default* name, keeping anvil-renamed names as-is. This assumes the English
    -- locale, but that makes some sense because we can't print non-Latin characters anyway.

    if (
        item.name == "minecraft:enchanted_book"
        and item.displayName == "Enchanted Book"
        and next(item.enchantments or {})
    ) then
        local enchantments = {}
        for _, enchantment in ipairs(item.enchantments) do
            table.insert(enchantments, enchantment.displayName)
        end
        return "\x15 " .. table.concat(enchantments, " + ")
    end

    if (
        (
            item.name == "minecraft:potion"
            or item.name == "minecraft:splash_potion"
            or item.name == "minecraft:lingering_potion"
        )
        and next(item.potionEffects or {})
        -- Filter out Spectrum's potions, since they can combine multiple effects with different
        -- durations.
        and stripFormatting(item.displayName) ~= ({
            ["minecraft:potion"] = "Pigment Potion",
            ["minecraft:splash_potion"] = "Splash Pigment Potion",
            ["minecraft:lingering_potion"] = "Lingering Pigment Potion",
        })[item.name]
    ) then
        local max_duration = 0
        local max_potency = 1
        for _, effect in pairs(item.potionEffects) do
            -- Computing the maximum duration is not obviously correct, but seems to check out for
            -- all vanilla potions.
            max_duration = math.max(max_duration, effect.duration or 0)
            max_potency = math.max(max_potency, effect.potency or 1)
        end
        -- A potent Potion of Slowness inflicts Slowness IV compared to the normal Slowness I, so we
        -- write "II" regardless of the effect potency. This covers everything except Potion of
        -- Turtle Master, which starts with a high potency and thus requires a higher cutoff.
        local default_potency = 1
        if item.displayName:match("Turtle Master") then
            default_potency = 4
        end
        local potency_part = ""
        if max_potency > default_potency then
            potency_part = " II"
        end
        local duration_part = ""
        if max_duration >= 3600 then
            duration_part = (" (%02d:%02d:%02d)"):format(
                math.floor(max_duration / 3600),
                math.floor(max_duration / 60) % 60,
                max_duration % 60
            )
        elseif max_duration > 0 then
            duration_part = (" (%02d:%02d)"):format(
                math.floor(max_duration / 60),
                max_duration % 60
            )
        end
        return item.displayName .. potency_part .. duration_part
    end

    local inferred_name = snakeCaseToTitleCase(item.name:match(":(.*)"))

    -- Smithing templates don't export their name anywhere. Match by display name exclusively
    -- because mods add their own smithing templates without setting any recognizable tags.
    if item.displayName == "Smithing Template" then
        return "\x08 " .. inferred_name:gsub(" Smithing Template$", "")
    end

    -- Similar thing for banner patterns, plus hard-coding for known patterns that don't follow
    -- the pattern.
    if item.displayName == "Banner Pattern" then
        local name = ({
            ["minecraft:flower_banner_pattern"] = "Flower Charge",
            ["minecraft:creeper_banner_pattern"] = "Creeper Charge",
            ["minecraft:skull_banner_pattern"] = "Skull Charge",
            ["minecraft:mojang_banner_pattern"] = "Thing",
            ["minecraft:piglin_banner_pattern"] = "Snout",
            ["minecraft:dragon_banner_pattern"] = "Dragon Charge",
            ["spectrum:logo_banner_pattern"] = "Color Theory",
        })[item.name] or inferred_name:gsub(" Banner Pattern$", "")
        return name .. " Banner Pattern"
    end

    -- The full names of music discs (author + title) can only be extracted by calling
    -- `getAudioTitle` on a disk drive, but since `getAudioTitle` runs on the computer thread, we
    -- can't push the disc into a disc drive, get the title, and move it back within a tick, so it'd
    -- quickly get messy. Hard-code the names instead.
    if item.tags["minecraft:music_discs"] and item.displayName == "Music Disc" then
        local name = discs[item.name] or ("Unknown - " .. inferred_name:gsub("^Music Disc ", ""))
        return "\x0f " .. name
    end

    -- Plenty of useful information is stored in NBT, but we don't have direct access to it, so we
    -- hard-code specific hashes. The hashes can be computed from sNBT using
    -- [nbtlib](https://pypi.org/project/nbtlib/) like this:
    --     nbt --plain -w '{Fireworks:{Flight:1b}}' /dev/stdout | md5sum
    if not item.nbt then
        return item.displayName
    end

    -- The default three rocket flight durations. No need to filter for display name here, since
    -- we're only changing names for known NBTs, and renaming affects the NBT.
    if item.name == "minecraft:firework_rocket" then
        -- {Fireworks:{Flight:Nb}}
        local flight_duration = ({
            ["d0ff6bc9806f9055938eb48aedf0c2d4"] = 1,
            ["2a39747329a0f0c6429c3a43d291a409"] = 2,
            ["eed0556fe00e36dbb354b0f833973efc"] = 3,
        })[item.nbt]
        if flight_duration then
            return "\x18 Flight duration " .. flight_duration
        end
    end

    if item.name == "minecraft:goat_horn" then
        -- {instrument:"minecraft:..._goat_horn"}
        local sound = ({
            ["ebcaa0a0c0569860e8c1896828aff6bc"] = "Ponder",
            ["f4851fff21ad8937ce60d581b886a4c1"] = "Sing",
            ["cb24dd66d7be3d4b5e1c73fea8a398fe"] = "Seek",
            ["d6c185ca11d6750f2c11493b0d8a258c"] = "Feel",
            ["8e4a5ae425abb90b07c76e85fb0a097e"] = "Admire",
            ["3c921ec6b4789b9351c999dd5cc36e42"] = "Call",
            ["c30632d04e95071c7b48b7b843828865"] = "Yearn",
            ["54ce224c49ee3a7e86fdb7f60bd0f387"] = "Dream",
        })[item.nbt]
        if sound then
            return sound .. " " .. item.displayName
        end
    end

    -- For containers that can have contents while in item form, disambiguate between empty and
    -- populated versions. Equate empty NBT with no NBT, since both can be present in different
    -- circumstances.
    if (
        (
            item.tags["c:shulker_boxes"]
            or item.tags["supplementaries:sacks"]
            -- Presents never have empty NBT, but otherwise behave the same.
            or item.name == "spectrum:present"
        )
        -- {BlockEntityTag:{Items:[],id:"minecraft:shulker_box"}}
        and item.nbt ~= "bc54a5748935980a545887a339976847"
    ) then
        local default_name = inferred_name
        -- Supplementaries Squared spells IDs like `sack_purple` while translating them like "Purple
        -- Sack", so it needs a small hack.
        if item.name:match("^suppsquared:sack_") then
            default_name = inferred_name:gsub("^Sack ", "") .. " Sack"
        end
        if item.displayName == default_name then
            return item.displayName .. " with items"
        end
    end

    -- It seems useful to disambiguate between nests/hives that are empty vs contain bees vs contain
    -- honey only, so we hard-code the default five honey levels as opposed to just the level 0.
    -- Don't filter for the default name here, since it's non-trivial to get (e.g. Friends & Foes
    -- renames the default beehive to "Oak Beehive") and people are unlikely to rename hives.
    if (
        item.name == "minecraft:bee_nest"
        or item.name == "minecraft:beehive"
        or item.name:match("^friendsandfoes:.*_beehive$")
    ) then
        -- {BlockEntityTag:{Bees:[]},BlockStateTag:{honey_level:"N"}}
        local honey_level = ({
            ["8dd5298dc53246c577f3b0baaa365fc9"] = 0,
            ["39b8373a630d3821fd8330d57172160d"] = 1,
            ["67e049292d3aa2d99fbbd7605e0b7733"] = 2,
            ["edd063c6746d63e89092ddadd86bbb0c"] = 3,
            ["376ebd29ee931d3bff919772592aeaa6"] = 4,
            ["4daa8ea9ebca9d7477d610a49d3e529f"] = 5,
        })[item.nbt]
        if honey_level == nil then
            return item.displayName .. " with bees"
        elseif honey_level > 0 then
            return item.displayName .. " with honey"
        end
    end

    if item.name == "supplementaries:cage" and item.displayName == "Cage" then
        return "Filled " .. item.displayName
    end

    if item.name == "supplementaries:lunch_basket" and item.displayName == "Lunch Basket" then
        -- {SelectedSlot:N}
        local selected_slot = ({
            ["fb8043f08eeff71170c3a484156606c8"] = 0,
            ["75abc772f41b13b164b4228d5fed9baa"] = 1,
            ["d05887fb2ade5806c0f141381a5d897e"] = 2,
            ["d9549e8b32dfa280556dd395afc8acae"] = 3,
            ["76425bd180df4830331884a915978a71"] = 4,
            ["218feebde48864e492b5db66ffb2be66"] = 5,
        })[item.nbt]
        if not selected_slot then
            return item.displayName .. " with food"
        end
    end

    if (
        item.name == "additionaladditions:pocket_jukebox"
        and item.displayName == "Pocket Jukebox"
        and item.nbt ~= "41883520c3071f5f4a4a4613fb005e0c" -- {}
    ) then
        return item.displayName .. " with disc"
    end

    if (
        item.name == "supplementaries:blackboard"
        and item.displayName == "Blackboard"
        -- {BlockEntityTag:{Pixels:[L;0L,0L,0L,0L,0L,0L,0L,0L,0L,0L,0L,0L,0L,0L,0L,0L]}}
        and item.nbt ~= "943fe9452c6f0c3306d7ba602b719d87"
    ) then
        return item.displayName .. " with drawing"
    end

    -- Suspicious Stew is not exposed deliberately, even though we could match NBT. At the current
    -- scale we use suspicious stew exclusively for gambling.

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
    -- Some items, like smithing templates and music discs, are formatted into a name that is not
    -- present as a substring in data. Recognize that.
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
    -- Push the cart in both directions at once. Since the cart is close to one end of the rail, it
    -- can speed up in the direction of the portal much more than in the opposite one, so this
    -- reliably sends the cart across dimensions.
    rail.pushMinecarts(false)
    rail.pushMinecarts(true)
end

return common
