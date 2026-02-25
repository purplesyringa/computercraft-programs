local named = require "named"
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
    local prompt = settings.get("shell.prompt", "@h @d> ")
    local hostname = tostring(os.computerID())
    if named.hasHostname() then
        hostname = named.hostname()
    end
    prompt = prompt:gsub("@h", hostname):gsub("@d", "/" .. shell.dir())
    write(prompt)
    term.setTextColor(colors.white)
end

local history = {}

local exit = false
local is_running = false
function shell.exit() exit = true end

parallel.waitForAny(function()
    while not exit do
        show_ps1()
        local input = read(nil, history, settings.get("shell.autocomplete") and shell.complete)
        if input:match("%S") and history[#history] ~= input then table.insert(history, input) end
        is_running = true
        shell.run(input)
        is_running = false
    end
end, function()
    while true do
        local _, reason = os.pullEventRaw("terminate")
        if reason == "hangup" then
            if is_running then
                -- Exit when the current process completes.
                shell.exit()
            else
                -- Exit immediately. This is necessary if a process is running, so `terminate` is
                -- delivered to it and not to `read`, and then the process quits immediately, so
                -- plain `shell.exit` would execute one more line than intended.
                break
            end
        end
    end
end)
