local runfs = require "runfs"
local svc = require "svc"

local function showGroupStatus(kind)
    local sysroot_items = {}
    for _, file_name in pairs(fs.list(fs.combine(svc.sysroot, kind))) do
        sysroot_items[file_name] = true
    end

    local items = {}
    local ok, impure_items = pcall(fs.list, fs.combine("impure", kind))
    if ok then
        for _, file_name in pairs(impure_items) do
            local name = file_name
            if kind == "targets" then
                name = name:gsub("[.]lua$", "")
            end
            table.insert(items, {
                name = name,
                is_override = sysroot_items[file_name],
            })
        end
        table.sort(items, function(a, b)
            return a.name < b.name
        end)
    end

    if not next(items) then
        print("No local " .. kind)
        return
    end

    write("Local " .. kind .. ": ")
    for i, info in pairs(items) do
        if i > 1 then
            write(", ")
        end
        write(info.name)
        if info.is_override then
            term.setTextColor(colors.red)
            write(" (override)")
            term.setTextColor(colors.white)
        end
    end
    print()
end

local function showStatus()
    write("Impure environment is ")
    if runfs.getImpure() then
        term.setTextColor(colors.yellow)
        write("enabled")
    else
        term.setTextColor(colors.green)
        write("disabled")
    end
    term.setTextColor(colors.white)
    print()
    showGroupStatus("packages")
    showGroupStatus("targets")
end

local args = { ... }

if #args == 0 or (#args == 1 and args[1] == "status") then
    showStatus()
elseif #args == 1 and args[1] == "enable" then
    runfs.setImpure(true)
    print("Impure environment enabled")
elseif #args == 1 and args[1] == "disable" then
    runfs.setImpure(false)
    print("Impure environment disabled")
else
    printError("Usage:")
    printError("    impure [status]")
    printError("    impure enable")
    printError("    impure disable")
end
