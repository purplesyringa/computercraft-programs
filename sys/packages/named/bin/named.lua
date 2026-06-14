local named = require "named"
local ok, own = pcall(named.hostname)
if ok then
    rednet.host("named", own)
end

while true do
    local sender, pattern = rednet.receive("named-request")
    if type(pattern) == "string" then
        ok, own = pcall(named.hostname)
        if not ok then
            own = nil
        end
        if (own or ""):match(pattern) then
            rednet.send(sender, own, "named-response")
        end
    end
end
