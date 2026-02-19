# async

An async runtime.

The API somewhat closely mirrors Rust's [`tokio`](https://docs.rs/tokio) runtime and its core properties, but sometimes takes inspiration from Python's `asyncio` and Erlang.

As typical in Lua, coroutines are inert and have to be driven to perform work -- either by another coroutine or by the async runtime. When resumed, coroutines perform synchronous work, start an asynchronous operation and schedule themselves to be woken up when the operation completes. Such an operation completes even if the coroutine is no longer polled or is cancelled. Tasks are a way to offload polling coroutines onto the async runtime. Tasks do not need to be polled by the user.

Since ComputerCraft is single-threaded, coroutines are never preempted and do not race with other coroutines, as long as the critical sections don't contain yield points.

This runtime completely replaces the function of the [`parallel`](https://tweaked.cc/module/parallel.html) module, offering more efficient and ergonomic functions, like `async.gather` and `async.race`. Using coroutines from `async` as arguments to `parallel` will fail.

## Pitfalls

ComputerCraft made some odd design decisions that we have to live with, and there are subtle issues you need to be aware of when writing asynchronous code.

### Lost wake-ups

I/O is driven by a single global event queue, tracking everything from asynchronous notifications to task completion. Tasks can subscribe to events using *filters*, and when an event arrives, it is delivered to *all* tasks with a matching filter. For example, you can have two tasks waiting on rednet or keyboard without losing notifications. However, the task has to be actually listening to the event to receive it: if you receive a rednet message and then execute an asynchronous operation before calling `rednet.receive` again, you will lose messages arriving in-between. Dedicating a task to exclusively receiving events and then passing them to a different task via queues or other message passing mechanisms acting as buffers is necessary to avoid losing wake-ups.

ComputerCraft has a hard limit of 256 events in queue, so wake-ups may be lost if more than 256 tasks are scheduled. The runtime can help limit concurrency with `async.newTaskSet`, `async.newSemaphore`, or `async.newMutex`.

### Performance

When an event arrives, the runtime only wakes up tasks with matching filters and doesn't iterate over other tasks, but this optimization relies on tasks actually communicating their filters. A common offender is the built-in [`parallel`](https://tweaked.cc/module/parallel.html) module, whose runners catch all events, so `async` offers filter-aware `async.gather` and `async.race` methods instead.

ComputerCraft's builtin functions have very coarse-grained filters. For example, [`rednet_message`](https://tweaked.cc/event/rednet_message.html) does not filter based on the protocol. Most prominently, [`task_complete`](https://tweaked.cc/event/task_complete.html) is used for all peripheral calls and does not offer any way to detect which coroutine wants to handle which event. The runtime contains a hacky best-effort optimization based on debug APIs, but it only works well if tasks waiting on `task_complete` are seldom cancelled and custom async runtimes are not used.

### Race conditions

While Lua programs are single-threaded, Lua code can race with Minecraft code.

For example, if you invoke [`peripheral.getType`](https://tweaked.cc/module/peripheral.html#v:getType) on a given side twice in a row without yielding, you may get different results if a player replaces the peripheral in the meantime. The [`peripheral`](https://tweaked.cc/event/peripheral.html) event corresponding to this replacement will be delivered, but only at the next yield at the very earliest.

Similarly, operations scheduled sequentially on the main thread, like [`inventory.getItemDetail`](https://tweaked.cc/generic_peripheral/inventory.html#v:getItemDetail), can be scheduled to different ticks if a tick occurs between scheduling the operations. Even if the operations are scheduled on the same tick and the responses are pushed to the event queue on the same tick, their responses can be handled on different ticks.


## Core API

The two core functions are `async.spawn` and `async.drive`. `async.spawn` spawns a new task, while `async.drive` executes all scheduled tasks in parallel. `async.drive` can only be executed once and should typically be the last statement in the program. A typical asynchronous program will look like this:

```lua
dofile(fs.combine(shell.getRunningProgram(), "../../pkgs.lua"))
local async = require "async"

async.spawn(function()
	-- Do an async operation
end)

async.spawn(function()
	-- Do another async operation, perhaps in a loop
	while true do
		-- Wait for some events and spawn a background task to handle the event.
		async.spawn(function()
			-- ...
		end)
	end
end)

async.drive()
```

### `async.spawn(function)`

Spawns a function as a task. The returned task object has the following API:

- `Task.finished()`: check if the task has completed.
- `Task.join()`: wait for the task to complete. Forwards its return values. If the task has already finished, returns the saved output immediately.
- `Task.cancel()`: delivers the `terminate` event to the task (typically causing it to throw a `Terminated` error, which is silently ignored) and then deschedules it. The task is considered to finish with an empty output, as if by `return`. If the task intercepts the event, it can perform some synchronous operations, but it's no longer polled, so asynchronous code is out of the window. Cancelling a completed task is a no-op.

The created task is considered *supervised* by the current task, which means that if the current task is cancelled, the child task is automatically cancelled as well. This is propagated in a chain-like reaction across trees. If a task completes out of its own volition, its children are not cancelled, unless a grandparent is cancelled.

Errors in background tasks terminate the entire runtime, except when occurring during `cancel`, in which case they are silently ignored. Use `async.spawn(function() pcall(...) end)` to catch errors if necessary.

When `async.spawn` is called, the coroutine executes synchronous actions up to the first yield point and schedules its first asynchronous action before `async.spawn` returns, so e.g.

```lua
async.spawn(function() chest.pullItems(...) end)
local item = chest.getItemDetail(...)
```

...is guaranteed to schedule `getItemDetail` after `pullItems`, so when `getItemDetail` completes, `item` will contain post-pulling info. Multiple background tasks are typically polled in order of spawning, but can diverge if they pull different events.

### `async.spawnDetached(function)`

Like `async.spawn`, but the task is spawned without supervision. If the current task is cancelled, the child keeps going. This is equivalent to `async.spawn` in a top-level context, i.e. when there is no current task.

### `async.drive()`

Poll background tasks to completion. The function completes when all tasks return, including the ones added after `async.drive` starts.


## Combinators

These combinators don't limit concurrency, possibly losing wake-ups on large tables. They also don't guarantee the order in which tasks are spawned, since the table iteration order can be arbitrary. If either is an issue, consider using `newTaskSet`, which gives more control.

### `async.gather({ [key] = task or function, ... })`

Wait for all tasks from the table to complete. Returns a table mapping each key to its (first) return value. Mirrors [`parallel.waitForAll`](https://tweaked.cc/module/parallel.html#v:waitForAll).

Each value can be either a task or a function. If it's a function, it is scheduled as a supervised task.

```lua
local results = async.gather({
	sleep = os.sleep(1),
	immediate = function()
		return 123, 456
	end,
})
assert(results.sleep == nil)
assert(results.immediate == 123)
```

### `async.race({ [key] = task or function, ... })`

Wait for any task from the table to complete. Returns the key of the first completed task, followed by all of its return values. Mirrors [`parallel.waitForAny`](https://tweaked.cc/module/parallel.html#v:waitForAny).

Each value can be either a task or a function. If it's a function, it will be scheduled as a supervised task. When the first task completes, all other tasks are cancelled.

```lua
local key, value1, value2 = async.race({
	sleep = os.sleep(1),
	immediate = function()
		return 123, 456
	end,
})
assert(key == "immediate")
assert(value1 == 123)
assert(value2 == 456)
```

### `async.timeout(duration, task or function)`

Wait for a task to complete until a given time limit. If the task completes in time, its return values are forwarded, otherwise the function returns nothing, as if by `return`.

`duration` is in seconds. If a function is passed as the second argument, it will be scheduled as a supervised task. The task is cancelled on timeout.

### `async.parMap({ [key] = value, ... }, function)`

Invokes `function(value, key)` for each entry in the table concurrently, returning a table of results with matching keys.

```lua
local result = async.parMap({ a = 1, b = 2 }, function(x)
	return x * 3
end)
assert(result.a == 3)
assert(result.b == 6)
```


## Task sets

Task sets offer a way to create a group of tasks which can be joined or cancelled together. Task sets keep track of spawned tasks automatically.

A task set can be created by calling `async.newTaskSet([concurrency_limit])`. If present, `concurrency_limit` limits the number of tasks that can run at once. The `TaskSet` API has the following methods:

- `TaskSet.spawn(function)`: creates a supervised task and returns a task object similarly to `async.spawn`. The task set remembers that it spawned this task. If there are already `concurrency_limit` running tasks in this task set, waits for a task to complete (either normally or by being cancelled) before spawning a new one.

- `TaskSet.join()`: wait for all spawned tasks to complete. Does not return anything. If necessary, individual return values can be obtained by calling `join` on task objects.

- `TaskSet.cancel()`: cancel all spawned tasks.

New tasks should not be added to the task set after `join` or `cancel` are called on the task set.

```lua
local task_set = async.newTaskSet(200)
local chest_contents = {}
for key, chest in pairs(chests) do
	task_set.spawn(function()
		chest_contents[key] = chest.list()
	end)
end
task_set.join()
```


## Actors

Actors offer a simple way to synchronize operations on a single (semantic) object across different event sources.

## `async.newQueue()`

The simplest design is to have a per-object request *queue* populated from arbitrary places in the program, which a single background task reads and handles. Pushing to a queue does not block, so it can be done almost anywhere.

`async.newQueue()` returns a queue object, which has the following methods:

- `Queue.put(...)`: add an entry to the queue. Can take multiple parameters.
- `Queue.get()`: wait for an entry to be placed in the queue, remove it, and return it (possibly as multiple values). The entries are popped in first-in-first-out order.

```lua
local messages = async.newQueue()

async.spawn(function()
	-- Since `put` doesn't block, this is guaranteed to not lose events.
	while true do
		messages.put(rednet.receive())
	end
end)

async.spawn(function()
	while true do
		local computer_id, msg, protocol = messages.get()
		-- `analyzeMessage` can be asynchronous and still won't lose events, since the queue acts as
		-- a buffer.
		analyzeMessage(computer_id, msg, protocol)
	end
end)
```

## `async.newNotifyOne()`

Queues consider entries independent, but you may often want to coaelsce events. For example, if you want to react to `turtle_inventory` events to rescan the inventory, and multiple `turtle_inventory` events arrive at once, you may want to consume them all at once. Unlike `Queue`, `NotifyOne` synchronizes over a single boolean, called *permit*, addressing this issue.

`async.newNotifyOne()` returns a `NotifyOne` object with the following API:

- `NotifyOne.notifyOne()`: flag the event as "ready". This sets the permit to `true` regardless of its previous value.
- `NotifyOne.wait()`: wait for the ready event. This waits for the permit to become `true` and then reset it to `false` atomically.

If `wait` is not running when `notifyOne` is called, the next call to `wait` returns immediately and then the permit is reset, so events are not lost. If `wait` is running while `notifyOne` is called, `wait` returns immediately. If multiple tasks run `wait` at the same time, `notifyOne` will only wake up one of them. You should usually only have one task waiting on the primitive, so this shouldn't matter much.

`notifyOne` does not yield, but merely schedules the waiting task to be woken up. The current task keeps going until its next yield point, so it is safe to use `notifyOne` in critical sections. The waiting task will be woken up before the next event arrives.

```lua
local turtle_inventory = async.newNotifyOne()

async.spawn(function()
	while true do
		os.pullEvent("turtle_inventory")
		turtle_inventory.notifyOne()
	end
end)

async.spawn(function()
	while true do
		-- Scan the inventory before waiting so that we have something to start with.
		scanInventory()
		turtle_inventory.wait()
	end
end)
```

## `async.newNotifyWaiters()`

`NotifyOne` can save a permit "for later" if `notifyOne` is invoked while `wait` is not running. This is not always the right semantics: say, if you recognize that some state is currently incorrect and want to wait for changes, you want to ignore outstanding permits and exclusively wait for future notifications. `NotifyWaiters` can help: it's similar to `NotifyOne`, but does not buffer permits. This also allows `notifyWaiters()` to wake up *all* tasks waiting on the primitive as opposed to just one.

`async.newNotifyWaiters()` returns a `NotifyWaiters` object with the following API:

- `NotifyWaiters.notifyWaiters()`: wake up all tasks calling `wait` on this object.
- `NotifyWaiters.wait()`: wait for `notifyWaiters`.

If `wait` is not running when `notifyWaiters` is called, `notifyWaiters` is a no-op.

`notifyWaiters` does not yield, but merely schedules the waiting tasks to be woken up. The current task keeps going until its next yield point, so it is safe to use `notifyWaiters` in critical sections. The waiting tasks will be woken up before the next event arrives.

```lua
local has_modem = peripheral.find("modem") ~= nil
local has_modem_updated = async.newNotifyWaiters()

async.spawn(function()
	while true do
		local name = os.pullEvent()
		if name == "peripheral" or name == "peripheral_detach" then
			has_modem = peripheral.find("modem") ~= nil
			-- `has_modem` may become outdated by the time `find` completes if the modem is detached
			-- on the main thread, but that will cause another event to be delivered, eventually
			-- fixing `has_modem`.
			has_modem_updated.notifyWaiters()
		end
	end
end)

local function waitForModem()
	while not has_modem do
		has_modem_updated.wait()
	end
end
```


## Utilities

### `async.subscribe(event, function)`

Starts a supervised task listening to `event`. Each time a matching event arrives, it invokes a callback with the event parameters as arguments.

There are multiple possible interpretations of what this might mean for asynchronous callbacks, so this function requires the passed callback to not yield. Consult examples for how to use asynchronous callbacks, depending on your needs.

```lua
-- Synchronous callback.
async.subscribe("char", function(ch)
	str = str .. ch
end)

-- Asynchronous callback, handling events concurrently.
async.subscribe("char", function(ch)
	async.spawn(function()
		someAsyncFn(ch)
	end)
end)

-- Asynchronous callback, handling events sequentially.
local queue = async.newQueue()
async.subscribe("char", function(ch)
	queue.put(ch)
end)
async.spawn(function()
	while true do
		someAsyncFn(queue.get())
	end)
end)

-- Asynchronous callback, coalescing successive events.
local notify = async.newNotifyOne()
async.subscribe("turtle_inventory", notify.notifyOne)
async.spawn(function()
	while true do
		notify.wait()
		someAsyncFn()
	end
end)
```


## Synchronization primitives

Note that since the runtime is single-threaded, synchronization primitives are not necessary to protect against races between tasks in general: critical sections without yield points are guaranteed to not be preempted. Even if asynchronous operations are in play, an actor model typically produces simpler and faster code than mutexes. Still, these primitives are sometimes useful for performing different operations on a single (semantic) object, so they are provided.

`Mutex` and `RwLock` are Rust-style: they wrap the data they are protecting as opposed to being stored next to the data. Since Lua is a GC language first and foremost, this does not protect from saving references to the inner object and accessing it after unlocking the mutex, but I find that it makes code easier to navigate regardless. You can use `nil` as the protected object to get a raw primitive.

Locking a mutex or an `RwLock` returns a *guard object*. The guard object gives out access to the protected object via its `value` attribute, and has an `unlock` method to unlock the guard. Accessing `value` or unlocking again after the guard is unlocked throws an error.

### `async.newMutex(value)`

Creates a mutex object wrapping `value`. The object has the following API:

- `Mutex.lock()`: wait and acquire the mutex. Returns a guard object.

The mutex is fair: lock requests are handled in a first-in-first-out order.

```lua
local mutex = async.newMutex(1)
-- ...
local guard = mutex.lock()
guard.value = transformValue(guard.value)
guard.unlock()
```

### `async.newRwLock(value)`

Creates an `RwLock` object wrapping `value`. The object has the following API:

- `RwLock.shared()`: wait and acquire the mutex in shared mode. Returns a guard object. This is typically used on the read side, but you are still allowed to write to `guard.value` if that's the semantics you need.
- `RwLock.unique()`: wait and acquire the mutex in unique mode. Returns a guard object. This is typically used on the write side.

The unique part of the `RwLock` is fair, but the `RwLock` in general is unfair: readers can starve writers.

```lua
local rw_lock = async.newRwLock(1)
-- ...
local guard = rw_lock.unique()
guard.value = transformValue(guard.value)
guard.unlock()
-- ...
local guard = rw_lock.shared()
consume(guard.value)
guard.unlock()
```

### `async.newSemaphore([value])`

Creates a semaphore with `value` permits, or `0` if the value is absent or `nil`. The returned object has the following API:

- `Semaphore.acquire()`: wait for a permit to be available and remove it atomically. Does not return anything.
- `Semaphore.release([n])`: makes `n` permits available (`1` by default).


## Raw primitives

This is the most low-level API exported by the runtime. You most likely don't need to use it: `async.notifyWaiters` effectively provides a thin type-safe wrapper over this API.

The API provides two methods:

- `async.waitOn(key)`: wait for `wakeBy` to be invoked on the key.
- `async.wakeBy(key)`: schedule all tasks waiting on the key to be woken up. This neither yields nor resumes any coroutines.

The key can be anything that can be a table key. Numbers are currently used as task IDs and strings are currently used as event names. Waking up the wrong object can confuse its synchronization logic, so you should never use anything but manually created tables as keys.
