-- Inventory layout:
-- Slot 1: universal scanner
-- Slot 2: fuel
-- Slots 3-16: output (pre-initialized with 1 item in each as filter)
-- Equipment slots: diamond pickaxe, chunk vial
-- Should be placed at the exactly specified Y level.

local ore_filter = "minecraft:ancient_debris"
local initial_y = 16
local return_at_count = 800

local blocks_walked = 0
local total_ores_collected = 0

while true do
    -- Scan for nearby ores with a stationary scanner to increase the radius and avoid wasting fuel.
    turtle.select(1)
    while not turtle.place() do
        turtle.dig()
    end
    local scanner = nil
    while scanner == nil do
        os.sleep(0.1)
        scanner = peripheral.wrap("front")
    end
    local blocks = scanner.scan("block", 24, ore_filter)
    turtle.dig()

    -- The scanner is always placed in the opposite direction to the turtle, so signs should be
    -- flipped. The coordinates are also relative to the scanner, not the turtle, so there's
    -- an off-by-one error as well.
    for key, block in pairs(blocks) do
        block.x = -block.x + 1
        block.z = -block.z
        -- Ignore blocks at Y = 4 and lower, since the turtle might get stuck in the bedrock floor.
        if initial_y + block.y <= 4 then
            blocks[key] = nil
        end
    end

    local fuel_to_consume = math.floor((turtle.getFuelLimit() - turtle.getFuelLevel()) / 800)
    turtle.select(2)
    turtle.refuel(fuel_to_consume)

    local current_x = 0
    local current_y = 0
    local current_z = 0
    local current_direction = 0 -- counts left turns

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
        getToCoords(block.x, block.y, block.z)
        total_ores_collected = total_ores_collected + 1
    end

    local function resetRotation()
        while current_direction % 4 ~= 0 do
            turtle.turnLeft()
            current_direction = current_direction + 1
        end
    end

    if total_ores_collected > return_at_count then
        -- Return to base.
        getToCoords(-blocks_walked, 0, 0)
        resetRotation()
        break
    else
        -- Move to the next section and repeat.
        getToCoords(49, 0, 0)
        blocks_walked = blocks_walked + 49
        resetRotation()
    end
end
