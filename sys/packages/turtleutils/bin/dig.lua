local n = tonumber(arg[1])
for i = 1, n do
    turtle.dig()
    turtle.forward()
    turple.digUp()
    turtle.digDown()
end
