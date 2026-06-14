local hostname = require "hostname"
local ok, own = pcall(hostname.hostname)
if ok then
    rednet.host("named", own)
end
