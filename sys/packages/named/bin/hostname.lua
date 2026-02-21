local named = require "named"

if arg[1] then
    named.setHostname(arg[1])
else
    print(named.hostname())
end
