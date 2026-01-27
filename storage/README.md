# Storage

An *instant* storage with a client-server model.

The server, clients, and a number of chests need to be in the same wired network. A single server can deposit items to and withdraw items from multiple clients.

As you write the search query in the client, 1 stack of each matching item is pulled into its inventory for preview. These previews are interactive: if you take out some of the items, the preview is immediately replenished. The inventory is updated *atomically within a single tick*, assuming your server runs on good enough hardware, so it feels very responsive. A lot of care is put into ensuring race conditions don't break anything. The server gracefully handles client disconnects.

The storage requires a significant number of empty cells to operate due to the race condition avoidance algorithms. I recommend allocating 1 empty double chest per client. If the server runs out of storage, it crashes by assertion; sorry.

The server can very quickly reindex the storage, taking 1 tick per chest. It could do everything in parallel, if not for [the 256 queued event limit](https://github.com/cc-tweaked/CC-Tweaked/issues/2371), but this should be plenty performant still. The storage is reindexed automatically when peripherals are added or removed, though doing this while clients are interacting with the storage can crash the server, so pay attention to that.
