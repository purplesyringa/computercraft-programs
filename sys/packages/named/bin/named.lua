local hostname = require "hostname"
local ok, own = pcall(hostname.hostname)
if ok then
    rednet.host("named", own)
end

while true do
    local sender = rednet.receive("named-request")
    ok, own = pcall(hostname.hostname)
    if not ok then
        own = nil
    end
    rednet.send(sender, own, "named-response")
end
