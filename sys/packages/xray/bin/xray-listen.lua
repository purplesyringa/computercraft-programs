local log = fs.open("log.txt", "a")

peripheral.find("modem", rednet.open)

while true do
    local _, msg, _ = rednet.receive("xray")
    local text = string.format("%s going %d,%d,%d -> %d,%d,%d", msg.label, msg.fromX, msg.fromY, msg.fromZ, msg.toX, msg.toY, msg.toZ)
    print(text)
    log.write(text .. "\n")
end
