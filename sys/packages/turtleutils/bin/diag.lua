local n = tonumber(arg[1])
for i = 1, n do
    while not turtle.forward() do
        turtle.dig()
    end
    while turtle.digUp() do end
    turtle.digDown()
    turtle.turnRight()
    while not turtle.forward() do
        turtle.dig()
    end
    while turtle.digUp() do end
    turtle.digDown()
    turtle.turnLeft()
end
