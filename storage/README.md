# Storage

This is an *instant* storage. As you write the search query in the client, 1 stack of each matching item is pulled into its inventory for preview. These previews are interactive: if you take out some of the items, the preview is immediately replenished. The inventory is updated *within a single tick* (assuming your server runs on good enough hardware), so it feels very responsive.

Even better, this storage uses a client-server model: a single server can deposit items to and withdraw items from multiple clients. A lot of care is put into ensuring this does not introduce any race conditions. The server gracefully handles client disconnects.

The storage requires a significant number of empty cells to operate. I recommend allocating 1 empty double chest per client. If the server runs out of storage, it crashes by assertion; sorry.

The server can very quickly reindex the storage, taking 1 tick per inventory. It does this automatically when peripherals are added or removed, though doing this while clients are using the storage can cause crashes, so be careful.
