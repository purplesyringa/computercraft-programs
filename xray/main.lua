local args = { ... }

local base_x = tonumber(args[1])
local base_y = tonumber(args[2])
local base_z = tonumber(args[3])
local direction = args[4]
local return_at_count = tonumber(args[5])

local current_direction = ({ -- counts left turns from east
    east = 0,
    north = 1,
    west = 2,
    south = 3,
})[direction]
local base_direction = current_direction
local principal_x = ({ 1, 0, -1, 0 })[1 + current_direction]
local principal_z = ({ 0, -1, 0, 1 })[1 + current_direction]

local ore_filter = "minecraft:ancient_debris"

local current_x = base_x
local current_y = base_y
local current_z = base_z
local sections_scanned = 0
local ores_collected = 0

local function resetRotation()
    while current_direction % 4 ~= base_direction % 4 do
        turtle.turnLeft()
        current_direction = current_direction + 1
    end
end

local function scan()
    -- Scan for nearby ores with a stationary scanner to increase the radius and avoid wasting fuel.
    turtle.select(1)
    while not turtle.place() do
        turtle.dig()
    end
    -- The scanner doesn't always get recognized immediately.
    local scanner = nil
    while scanner == nil do
        os.sleep(0.1)
        scanner = peripheral.wrap("front")
    end
    local blocks = scanner.scan("block", 24, ore_filter)
    local _, scanner_info = turtle.inspect()
    local scanner_facing = scanner_info.state.facing
    turtle.dig()

    for key, block in pairs(blocks) do
        -- The scanner is stupid. Normally, it's faced in the opposite direction of the turtle, but
        -- in lava, it seems to be placed in the same direction. This means that signs can be
        -- flipped conditionally on the scanner's orientation, so we have to inspect it to fix the
        -- issue. At least it scans the same area regardless of orientation.
        local dx, dz
        if scanner_facing == "east" then
            dx, dz = block.x, block.z
        elseif scanner_facing == "north" then
            dx, dz = block.z, -block.x
        elseif scanner_facing == "west" then
            dx, dz = -block.x, -block.z
        elseif scanner_facing == "south" then
            dx, dz = -block.z, block.x
        end
        -- There's an off-by-one error because the coordinates are relative to the scanner, not the
        -- turtle. But *this* depends on the turtle's orientation, not the scanner's.
        if current_direction % 4 == 0 then
            dx = dx + 1
        elseif current_direction % 4 == 1 then
            dz = dz - 1
        elseif current_direction % 4 == 2 then
            dx = dx - 1
        elseif current_direction % 4 == 3 then
            dz = dz + 1
        end
        block.x = current_x + dx
        block.z = current_z + dz
        block.y = current_y + block.y
        -- Ignore blocks at Y = 4 and lower, since the turtle might get stuck in the bedrock floor.
        if block.y <= 4 then
            blocks[key] = nil
        end
    end

    return blocks
end

local function refuel()
    -- `turtle.refuel` ceils by default, so compute the count manually.
    local fuel_to_consume = math.floor((turtle.getFuelLimit() - turtle.getFuelLevel()) / 800)
    turtle.select(2)
    turtle.refuel(fuel_to_consume)
end

local function broadcast(msg)
    -- Temporarily replace the pickaxe with the ender modem to send a message. Wouldn't want to
    -- replace a chunk vial!
    turtle.select(3)
    turtle.equipLeft()
    while peripheral.wrap("left") == nil do
        os.sleep(0.1)
    end
    rednet.open("left")
    rednet.broadcast(msg, "xray")
    turtle.equipLeft()
end

local function walkFor(n)
    for i = 1, n do
        while not turtle.forward() do
            turtle.dig()
        end
    end
end

local function getToCoords(x, y, z)
    -- Translate to the local coordinate system.
    local dx = x - current_x
    local dz = z - current_z
    if current_direction % 4 == 1 then
        dx, dz = -dz, dx
    elseif current_direction % 4 == 2 then
        dx, dz = -dx, -dz
    elseif current_direction % 4 == 3 then
        dx, dz = dz, -dx
    end
    -- Optimize the number of rotations.
    if dx > 0 then
        walkFor(dx)
    end
    if dz > 0 then
        turtle.turnRight()
        current_direction = current_direction - 1
        walkFor(dz)
    elseif dz < 0 then
        turtle.turnLeft()
        current_direction = current_direction + 1
        walkFor(-dz)
    end
    if dx < 0 then
        if dz > 0 then
            turtle.turnRight()
            current_direction = current_direction - 1
        elseif dz < 0 then
            turtle.turnLeft()
            current_direction = current_direction + 1
        else
            turtle.turnLeft()
            turtle.turnLeft()
            current_direction = current_direction + 2
        end
        walkFor(-dx)
    end
    current_x = x
    current_z = z

    -- Vertical movement.
    while current_y < y do
        while not turtle.up() do
            turtle.digUp()
        end
        current_y = current_y + 1
    end
    while current_y > y do
        turtle.digDown()
        turtle.down()
        current_y = current_y - 1
    end
end

while true do
    -- Face the original direction so that we scan the same line of blocks every time.
    resetRotation()
    local blocks = scan()
    refuel()

    while next(blocks) do
        -- Find the closest block to the current location.
        local min_distance = nil
        local min_distance_key = nil
        for key, block in pairs(blocks) do
            local distance = (
                math.abs(block.x - current_x)
                + math.abs(block.y - current_y)
                + math.abs(block.z - current_z)
            )
            if min_distance == nil or distance < min_distance then
                min_distance = distance
                min_distance_key = key
            end
        end
        local block = blocks[min_distance_key]
        blocks[min_distance_key] = nil
        broadcast({
            label = os.getComputerLabel(),
            fromX = current_x,
            fromY = current_y,
            fromZ = current_z,
            toX = block.x,
            toY = block.y,
            toZ = block.z,
        })
        getToCoords(block.x, block.y, block.z)
        ores_collected = ores_collected + 1
    end

    if ores_collected > return_at_count then
        -- Return to base and reset rotation for consistency.
        getToCoords(base_x, base_y, base_z)
        resetRotation()
        break
    else
        -- Move to the next section and repeat.
        sections_scanned = sections_scanned + 1
        local distance = sections_scanned * 49
        getToCoords(base_x + principal_x * distance, base_y, base_z + principal_z * distance)
    end
end
