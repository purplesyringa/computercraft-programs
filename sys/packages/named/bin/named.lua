local named = require "named"
local ok, own = pcall(named.hostname)
if ok then
    named._hostHostname(own)
end

while true do
    local sender, pattern = rednet.receive("named-request")
    if type(pattern) == "string" then
        local ok, hostname = named._ownHostnameMatchesPattern(pattern)
        if ok then
            rednet.send(sender, hostname, "named-response")
        end
    end
end
