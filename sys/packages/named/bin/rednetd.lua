-- rednet.open fails if `side` is not a modem. It also fails if the modem was disconnected between
-- peripheral.find and rednet.open. Both situations can be handled with a single pcall. Convenient!
peripheral.find("modem", function(side)
    pcall(rednet.open, side)
end)
while true do
    local _, side = os.pullEvent("peripheral")
    pcall(rednet.open, side)
end
