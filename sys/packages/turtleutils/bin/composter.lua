hoppers = { peripheral.find("minecraft:hopper") }
output = peripheral.find("minecraft:barrel")
while true do
    for _, hopper in pairs(hoppers) do
        for slot, item in pairs(hopper.list()) do
            if item.name == "minecraft:bone_meal" then
                output.pullItems(peripheral.getName(hopper), slot)
            end
        end
    end
    os.sleep(1)
end
