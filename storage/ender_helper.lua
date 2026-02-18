local async = require "../async"
local common = require "common"
local util = require "util"

peripheral.find("modem", rednet.open)

local wired_modem = peripheral.find("modem", function(_, modem)
    return not modem.isWireless()
end)
assert(wired_modem, "wired modem not found")
local wired_name = wired_modem.getNameLocal()
assert(wired_name, "modem disconnected from network")

local awaited_pong = nil
local inventory_adjusted = async.newNotifyWaiters()
local inventory_adjusted_message = nil

local function ping()
    local ping_id = math.random(1, 2147483647)
    awaited_pong = {
        id = ping_id,
        received = async.newNotifyOne(),
        server_id = nil,
    }
    rednet.broadcast({ type = "ping", id = ping_id }, "purple_storage")
    awaited_pong.received.wait()
    return awaited_pong.server_id
end

local function adjustInventory(server_id, rail, current_inventory, goal_inventory)
    local needs_retry = true
    while needs_retry do
        rednet.send(server_id, {
            type = "adjust_inventory",
            client = peripheral.getName(rail),
            current_inventory = current_inventory,
            goal_inventory = goal_inventory,
            preview = false,
        }, "purple_storage")
        inventory_adjusted.wait()
        needs_retry = inventory_adjusted_message.needs_retry
    end
end

local function handleOrder(rail, goal_inventory)
    -- We can't hold all items in our inventory at once: when we reset the minecart's cooldown, we'd
    -- need to fit the 15 withdrawn items, an empty bucket, and the cart in 16 slots. We could fill
    -- the bucket and move it to an equipment slot, but we'd have to do that regardless of whether
    -- refuel is necessary. A simple solution is to tell the server to operate directly on the cart.

    -- Get ready to break the cart: take out the bucket and items.
    local has_bucket = rail.pushItems(wired_name, 27, nil, 1) ~= 0

    local server_id
    local current_inventory = async.parMap(util.iota(16), rail.getItemDetail)
    local key = async.race({
        sleep = util.bind(os.sleep, 15),
        adjust = function()
            server_id = ping()
            adjustInventory(server_id, rail, current_inventory, {})
        end,
    })
    -- If adjustment times out, the cart is not guaranteed to be empty, so we can't reset its
    -- cooldown by breaking it. But since we timeout for 15s, the natural cooldown has already
    -- passed and we don't have to worry about it.
    if key == "adjust" then
        -- Reset cooldown.
        turtle.select(2)
        turtle.attack()
        turtle.place()

        key = async.race({
            sleep = util.bind(os.sleep, 5),
            adjust = util.bind(adjustInventory, server_id, rail, {}, goal_inventory),
        })
    end

    if has_bucket then
        turtle.select(1)
        turtle.placeDown()
        while turtle.getItemDetail(1).name ~= "minecraft:lava_bucket" do
            turtle.placeDown()
        end
    end
    rail.pullItems(wired_name, 1, nil, 27)

    common.sendCartToPortal(rail)

    if key == "sleep" then
        return "Operation timed out"
    end
end

local orders = {}
local orders_available = async.newNotifyWaiters()

async.spawn(function()
    while true do
        local rail, cart = common.wrapRailWired("front")
        if cart then
            local order = orders[cart.uuid]
            -- An order might be missing if we're currently sending this cart to the nether.
            if order then
                -- Tell other helpers to stop spinning for this cart.
                rednet.broadcast({ type = "order_taken", cart = cart.uuid }, "purple_storage")
                orders[cart.uuid] = nil
                local error_message = handleOrder(rail, order.goal_inventory)
                rednet.broadcast({
                    type = "order_delivered",
                    cart = cart.uuid,
                    error_message = error_message,
                }, "purple_storage")
            end
        end
        if next(orders) then
            os.sleep(0.1)
        else
            orders_available.wait()
        end
    end
end)

async.spawn(function()
    while true do
        local computer_id, msg = rednet.receive("purple_storage")
        if msg.type == "inventory_adjusted" then
            -- `notifyWaiters` guarantees that a delayed response (occurring for whatever reason)
            -- doesn't store a permit that can be interpreted as an immediate response later.
            inventory_adjusted_message = msg
            inventory_adjusted.notifyWaiters()
        elseif msg.type == "place_order" then
            -- We don't know if the cart will arrive on our rail, so wait for it regardless of who
            -- it originated from. When one helper acknowledges the cart, everyone else stops
            -- spinning.
            orders[msg.cart] = msg
            orders_available.notifyWaiters()
        elseif msg.type == "order_taken" then
            orders[msg.cart] = nil
        elseif msg.type == "pong" then
            if awaited_pong and msg.id == awaited_pong.id then
                awaited_pong.server_id = computer_id
                awaited_pong.received.notifyOne()
            end
        end
    end
end)

async.drive()
