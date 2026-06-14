local named = require "named"
local ok, own = pcall(named.hostname)
if ok then
    rednet.host("named", own)
end
