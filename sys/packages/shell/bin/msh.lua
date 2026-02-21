local svc = require "svc"
local shell = svc.makeNestedShell(_ENV)

local args = { ... }
if #args ~= 0 then
    shell.execute(...)
    return
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.yellow)
print(os.version(), "meow")
term.setTextColor(colors.white)

if settings.get("motd.enable") then
    shell.run("motd")
end

settings.define("shell.prompt", {
    description = "PS1, but configurable!",
    type = "string",
})

local function show_ps1()
    -- TODO: escape sequences for colors?
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    local prompt = settings.get("shell.prompt", "@d> ")
    prompt = prompt:gsub("@d", "/" .. shell.dir())
    write(prompt)
    term.setTextColor(colors.white)
end

local history = {}

local exit = false
function shell.exit() exit = true end

while not exit do
    show_ps1()
    local input = read(nil, history, settings.get("shell.autocomplete") and shell.complete)
    if input:match("%S") and history[#history] ~= input then table.insert(history, input) end
    if input == "reboot!" then os.reboot() end
    if input == "shutdown!" then os.shutdown() end
    shell.run(input)
end
