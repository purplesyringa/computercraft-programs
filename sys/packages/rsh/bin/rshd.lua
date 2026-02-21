local named = require "named"
local svc = require "svc"

local open_sessions = {}

local function closeAll(reason)
    for id, params in pairs(open_sessions) do
        rednet.send(params.client, {
            type = "close",
            session = params.session,
            reason = reason,
        }, "rsh")
    end
end

local old_reboot = os.reboot
os.reboot = function()
    closeAll("reboot")
    old_reboot()
end

local old_shutdown = os.shutdown
os.shutdown = function()
    closeAll("shutdown")
    old_shutdown()
end

rednet.host("rsh", named.hostname())
while true do
    local client_id, msg = rednet.receive("rsh")
    if msg.type == "open" then
        local params = msg
        params.client = client_id
        local id = string.format("%d:%d", params.client, params.session)
        open_sessions[id] = params
        svc.startProcess("rsh-serve-session " .. id, function()
            shell.execute("rsh-serve-session", textutils.serialize(params))
            open_sessions[id] = nil
        end, function()
            open_sessions[id] = nil
        end)
    elseif msg.type == "event" then
        local id = string.format("%d:%d", client_id, msg.session)
        if not open_sessions[id] then
            rednet.send(client_id, {
                type = "server_reset",
                session = msg.session,
            }, "rsh")
        end
    end
end

async.drive()
