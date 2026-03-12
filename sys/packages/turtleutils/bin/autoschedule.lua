local st = assert(peripheral.find("Create_Station"), "no station?")
assert(peripheral.getName(st) == "front", "wrong orientation")
local args = { ... }
if #args == 0 then
    printError("autoschedule <train_count>")
    return
end
local train_count = tonumber(args[1])
local train_seen = 0
local trains = {}
turtle.suck()
while train_seen < train_count do
    local _, _ = os.pullEvent("train_arrival")
    local train = st.getTrainName()
    if not trains[train] then
        trains[train] = true
        train_seen = train_seen + 1
        print(textutils.formatTime(os.time("local"), true), train)
        turtle.drop()
        os.sleep(1)
        turtle.suck()
    end
end
