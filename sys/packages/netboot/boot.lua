os._bt = os.clock()

settings.define("netboot.upstream", {
    description = "netboot server tag",
    default = "primary",
    type = "string",
})
local tag = settings.get("netboot.upstream")
print("Booting from " .. tag .. "...")

local _, payload, side
parallel.waitForAny(function()
    peripheral.find("modem", function(side)
        pcall(rednet.open, side)
    end)
    while true do
        rednet.broadcast(nil, "netboot-request@" .. tag)
        repeat
            _, side = os.pullEvent("peripheral")
        until pcall(rednet.open, side)
    end
end, function()
    _, payload, _ = rednet.receive("netboot-response@" .. tag)
end)
load(payload, "=netboot", nil, _ENV)(...)
