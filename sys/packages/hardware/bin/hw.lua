local hardware = require "hardware"
local tableui = require "tableui"

local function matchesGlob(name, glob)
    return name:find("^" .. glob:gsub("%.", "%."):gsub("%*", ".*") .. "$") ~= nil
end

local function showList(glob)
    local mapping = hardware.listAll()

    local names = {}
    local assigned_natives = {}
    for name, native_name in pairs(mapping) do
        table.insert(names, name)
        assigned_natives[native_name] = true
    end
    table.sort(names)

    term.setTextColor(colors.green)
    local writeRow = tableui.header({
        { key = "name", heading = "Name", width = 16 },
        { key = "assignment", heading = "Assignment", width = 16 },
        { key = "type", heading = "Type" },
    })
    for _, name in ipairs(names) do
        if matchesGlob(name, glob) then
            local type
            if mapping[name] == "default" then
                -- As a special case in `getty`, monitors and keyboards named `default` refer to the
                -- built-in devices thatdon't exist as peripherals. Don't error on that.
                type = "marker"
            else
                type = peripheral.getType(mapping[name])
            end
            if type then
                term.setTextColor(colors.white)
            else
                term.setTextColor(colors.red)
            end
            writeRow({
                name = name,
                assignment = mapping[name],
                type = type or "disconnected",
            })
        end
    end

    if glob == "*" or glob == "unnamed" then
        term.setTextColor(colors.gray)
        for _, name in ipairs(peripheral.getNames()) do
            if not assigned_natives[name] then
                writeRow({
                    name = "unnamed",
                    assignment = name,
                    type = peripheral.getType(name),
                })
            end
        end
    end
end

local function addPeripheral(name, value)
    local old_value = hardware.resolve(name)
    if old_value then
        printError(name, "is already assigned to", old_value)
        return
    end

    if not hardware._parseName(name) then
        printError(name, "is not a valid name")
        return
    end

    if not value then
        if peripheral.find("modem") then
            print("Connect a peripheral for", name, "over wired network")
            print("Use `hw add", name, "<side>` to add a direct connection")
        else
            printError("No modem connected, wired network unavailable")
            print("Use `hw add", name, "<side>` to add a direct connection")
            return
        end

        while true do
            local _, native_name = os.pullEvent("peripheral")
            local is_direct = (
                native_name == "front"
                or native_name == "back"
                or native_name == "left"
                or native_name == "right"
                or native_name == "top"
                or native_name == "bottom"
            )
            if not is_direct then
                value = native_name
                break
            end
        end
    end

    hardware.set(name, value)
    print("Assigned", name, "=", value)
end

local function removePeripheral(name)
    local old_value = hardware.resolve(name)
    if old_value then
        hardware.set(name, nil)
        print("Removed assignment", name, "=", old_value)
    else
        printError(name, "is not defined")
    end
end

local args = { ... }

if #args == 0 or (#args == 1 and args[1] == "list") then
    showList("*")
elseif #args == 2 and args[1] == "list" then
    showList(args[2])
elseif (#args == 2 or #args == 3) and args[1] == "add" then
    addPeripheral(args[2], args[3])
elseif #args == 2 and args[1] == "del" then
    removePeripheral(args[2])
else
    printError("Usage:")
    printError("    hw")
    printError("    hw list [<glob>]")
    printError("    hw add <name> [<side>]")
    printError("    hw del <name>")
end
