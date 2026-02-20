# wakey-wakey

Allows asynchronous code to run in synchronous contexts under certain conditions.

## Why?

There is sometimes a need to monkey-patch synchronous functions with yielding functions. For example, NFS wants to replace various APIs from `fs`, which doesn't normally yield, with calls over the network.

When this is done straightforwardly, an issue arises: if the caller of the synchronous API is waiting for an event, and the event arrives while the async operation is underway, it will be received by the async function, promptly ignored, and not delivered to the caller. For example, this can cause the shell to lose key presses while auto-completing paths over NFS.

Wakey-wakey queues events delivered while the async function is running, and when it ends, delivers them to the calling coroutine again. Notably, this only works if the calling coroutine is connected to some async runtime (`parallel`, `multishell`, `async` all work), which is typically the case. A possible exception is manually implemented generators, in which case there isn't much we can do.

## Usage

- `wakeywakey.toSync(f)`: translate an asynchronous function to a synchronous function. The core of the library.
- `wakeywakey.toAsync(f)`: translate a synchronous function back to an asynchronous function. This is the inverse of `toSync` in the sense that `toAsync(toSync(f)) == f`. Acts as a no-op for functions not produced by `toSync`. Provided for use in async-aware code for efficiency.
