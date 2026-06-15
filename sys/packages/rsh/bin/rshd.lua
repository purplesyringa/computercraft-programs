local named = require "named"
local svc = require "svc"

local open_sessions = {}

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
        -- Reset connection if the server was restarted and the `rsh-serve-session` process is known
        -- to be non-existent. This reacts to `rshd` restarts as well, probably suboptimal.
        if not open_sessions[id] then
            rednet.send(client_id, {
                type = "server_reset",
                session = msg.session,
            }, "rsh")
        end
    end
end

async.drive()
