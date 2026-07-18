local booted = os.clock()
print("Booting from network...")
local _, payload, side
parallel.waitForAny(function()
    peripheral.find("modem", function(side)
        pcall(rednet.open, side)
    end)
    while true do
        rednet.broadcast(nil, "netboot-request")
        repeat
            _, side = os.pullEvent("peripheral")
        until pcall(rednet.open, side)
    end
end, function()
    _, payload, _ = rednet.receive("netboot-response")
end)
load(payload, "=netboot", nil, _ENV)(booted)
