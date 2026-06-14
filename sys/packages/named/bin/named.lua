local hostname = require "hostname"
local ok, own = pcall(hostname.hostname)
if ok then
    rednet.host("named", own)
end

while true do
    local sender, pattern = rednet.receive("named-request")
    ok, own = pcall(hostname.hostname)
    if not ok then
        own = nil
    end
    if (own or ""):match(pattern) then
        rednet.send(sender, own, "named-response")
    end
end
