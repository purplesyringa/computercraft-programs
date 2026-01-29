# Storage

An *instant* storage with a client-server model.

The server, clients, and a number of chests need to be in the same wired network. A single server can deposit items to and withdraw items from multiple clients.

As you write the search query in the client, 1 stack of each matching item is pulled into its inventory for preview. These previews are interactive: if you take out some of the items, the preview is immediately replenished. The inventory is updated *atomically within a single tick*, assuming your server runs on good enough hardware, so it feels very responsive. A lot of care is put into ensuring race conditions don't break anything. The server gracefully handles client disconnects.

The storage requires a significant number of empty cells to operate due to the race condition avoidance algorithms. I recommend allocating 1 empty double chest per client. If the server runs out of storage, it crashes by assertion; sorry.

The server can very quickly reindex the storage, taking 1 tick per chest. It could do everything in parallel, if not for [the 256 queued event limit](https://github.com/cc-tweaked/CC-Tweaked/issues/2371), but this should be plenty performant still. The storage is reindexed automatically when peripherals are added or removed, though doing this while clients are interacting with the storage can crash the server, so pay attention to that.


## Protocol

The client-server protocol is designed to be simple to use for custom clients, so that you can request or deposit items programmatically.

A client should always be a turtle.

The rednet protocol used is `purple_storage`. The protocol supports automatic server discovery: the client should broadcast its messages until it receives a message from the server, at which point it knows what computer ID the server has and can send future messages directly.


### Index

The index API allows the client to keep track of which items are available in the storage.

When the client boots, it should send the following message:

```lua
{
	type = "request_index",
}
```

The server will then reply with a message of the following kind:

```lua
{
	type = "patch_index",
	items = { [key] = item, ... }
    reset = true,
    fullness = 0..100,
}
```

`items` is an associative array of items. The values are [the detailed information](https://tweaked.cc/reference/item_details.html) of items, where `count` represents the total number of items in the storage. `key` should be treated as a unique opaque key, but can be computed as `util.getItemKey(item)` if necessary.

`fullness` is an integer representing the percentage of the storage that is full.

`reset = true` indicates that `items` contains the complete index. Normally, when the server recognizes that the counts of certain items changed, it sends `patch_index` messages with `reset = false` and `items` containing only the difference from the previous index. `reset = true` is sent under three conditions: when the server boots, when it reindexes the storage, or when a client requests the index.

Clients are expected to keep local copies of the index, watch the rednet for `patch_index` messages, and patch the local copy from `items`, replacing it entirely if a patch with `reset = true` arrives:

```lua
index = {}
while true do
    local _, msg = rednet.receive("purple_storage")
    if msg.type == "patch_index" then
        if msg.reset then
            index = {}
        end
        for key, item in pairs(msg.items) do
            index[key] = item
        end
    end
end
```

Note that when all items of a given type are removed, the item will have `count = 0`. You may wish to ignore all such items.


### Adjustment

The core of the protocol is *adjustment*. With `adjust_inventory`, a client can request the server to adjust its inventory to a given state. Excess items are deposited into the storage, while absent items are pulled from the storage.

```lua
{
    type = "adjust_inventory",
    client = ...,
    current_inventory = { [slot] = item, ... },
    goal_inventory = { [slot] = item, ... },
    preview = false/true,
}
```

`client` should be the wired name of the turtle and can be obtained by the client via [`modem.getNameLocal()`](https://tweaked.cc/peripheral/modem.html#v:getNameLocal).

`current_inventory` represents the state of the inventory that the turtle currently has. This is necessary because the server cannot query a turtle's inventory. It should be a table mapping a slot to [the detailed information](https://tweaked.cc/reference/item_details.html) of the item in that slot. This is similar to [`inventory.list()`](https://tweaked.cc/generic_peripheral/inventory.html#v:list), but contains detailed information instead of basic information. Here are two examples on how to get it:

```lua
local function loadInventorySync()
	local inventory = {}
	for slot = 1, 16 do
        inventory[slot] = turtle.getItemDetail(slot, true)
	end
	return inventory
end

local function loadInventoryAsync()
    return async.parMap(util.iota(16), function(slot)
        return turtle.getItemDetail(slot, true)
    end)
end
```

`goal_inventory` should have the same format. An absent entry for a slot means that the slot should be emptied. For example, setting `goal_inventory = {}` deposits the entire inventory.

`preview` indicates whether the pushed items should logically be still considered part of the storage, in that they are counted in `count` and can be forcibly pulled back by the server if necessary. `preview = true` makes the items available to other clients, while `preview = false` guarantees that the server will not touch the client's inventory.

When the server finishes adjustment, it sends the following message:

```lua
{
	type = "inventory_adjusted",
	new_inventory = { [slot] = item, ... },
}
```

`new_inventory` contains the state of the inventory the server believes the client now has in the same format as `goal_inventory`. There are two subtle issues here:

1. `new_inventory` may not be equal to `goal_inventory` if some requests could not be satisfied:
	a. If the `count` in `goal_inventory` was higher than the number of items present, `new_inventory` may have a smaller `count` or even be `nil` in that slot. Note that you should always be ready for this situation, since another client can pulls items from the storage concurrently.
	b. Pulling for preview will never forcibly pull from other clients' previews, so in that case you can get a smaller `count` even if `count` is within the number of items in the storage.

2. `new_inventory` may not be equal to the actual inventory as seen by the client if a user changes the client's inventory concurrently. This is only an issue if you expect the client's inventory to be interacted with by anyone except the client.

`inventory_adjusted` always arrives within a few ticks after `adjust_inventory`, but can fail to arrive if the server stops or restarts. A 1-second timeout is recommended to avoid hangs, but you may need to adjust the timings depending on your hardware:

```lua
async.timeout(1, inventory_adjusted.wait)
```


### Triggering readjustment

The general shape of automatic readjustment is like this:

```lua
local readjust = async.newNotify()
async.spawn(function()
    while true do
        rednet.send(server_id, {
            type = "adjust_inventory",
            client = ...,
            current_inventory = loadInventory(),
            goal_inventory = goal_inventory,
            preview = ...,
        }, "purple_storage")
        -- not shown: wait for `inventory_adjustment` to arrive here
        readjust.wait()
    end
end)
```

Readjustment should be serialized, with a request only being sent after the previous completes. A "notify" primitive implements the right semantics. It also allows readjustment to be triggered from multiple sources, which we now go over one by one.

#### Inventory changes

This is only necessary if you want a user to interact with your client's inventory.

To recognize when a user adds or removes items from its inventory, the client can listen to the `turtle_inventory` event. Since this event can arrive during adjustment (either due to the user concurrently updating the inventory, or due to the server's own actions), you need to wait until adjustment completes before sending `adjust_inventory` again:

```lua
async.subscribe("turtle_inventory", readjust.notify)
```

Note that if `turtle_inventory` arrives for the second time due to the server's actions, the server will have nothing to do on this next adjustment request, and so `turtle_inventory` won't arrive for the third time and trigger an infinite loop.

#### Index updates

You may want to trigger readjustment if new items or more items of a given type arrive in the index.

Note that it is *incorrect* to trigger readjustment on every index change. Specifically, the server sends index updates even if *no item counts are changed* to propagate `fullness` updates. Readjustment should only be triggered if `items` is non-empty:

```lua
if next(msg.items) then
	readjust.notify()
end
```

Note also that the server can send an index update for an item even if `count` stays the same, and readjustment *should* often be triggered under this condition. This situation occurs if the server pulls a preview from the client -- this does not affect the count of the items in the storage, since a preview is logically considered part of the storage, but it *does* allow more items to be pulled if you're pulling for preview.

#### Inventory requests

This is only necessary if you use previews.

When the server reboots or reindexes the storage, it cannot automatically index your client's inventory for previews, since turtles don't implement the inventory API. Instead, the server sends a message asking clients to submit their inventories:

```lua
{
    type = "request_inventory",
}
```

The inventories should be submitted as the `current_inventory` field of the `request_adjustment` message, making the handling of this message trivial:

```lua
if msg.type == "request_inventory" then
    readjust.notify()
end
```


### Connectivity checks

The server can notify a client when the client's inventory is disconnected from the wired network. This can occur by accident if a user right-clicks the wired modem and acts as a sanity check. This is necessary because a turtle cannot detect this condition by itself except by polling.

Specifically, each time a peripheral is connected or disconnected, the server broadcasts the following message:

```lua
{
	type = "peripherals_changed",
}
```

Clients can then call `modem.getNameLocal()` to verify if they are still connected, depending on whether the function returns a string or `nil`.
