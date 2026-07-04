local mimic = peripheral.wrap("left")
mimic.setMimic({ block = "create:industrial_iron_window" })
while true do
    local ok, block = turtle.inspectUp()
    if ok and block.name == "minecraft:cauldron" then
        turtle.placeDown()
        turtle.placeUp()
    end
    os.sleep(1)
end
