# redirect

Helper library for running coroutines with redirected terminal and event sources.

## Usage

### `redirect.runWithTerm(redirect, f, ...)`

Mostly equivalent to `f(...)`. Each time the coroutine is resumed, the terminal is redirected to `redirect`, and each time it yields, the terminal is redirected back. If `f` errors, the error is printed to `redirect` as if by [`printError`](https://tweaked.cc/module/_G.html#v:printError) and the function returns. This function never fails (as long as the arguments have valid types) and always returns nothing, ignoring the return value of `f`.

### `redirect.runWithEventSource(f, ...)`

Spawns `f(...)` in a coroutine and waits for the delivery of events. This function automatically keeps track of active filters and just waits for you to push events from outside, resuming the coroutine as necessary. Returns an object with two methods:

- `pushEvent(name, ...)`: deliver an event. The arguments will be returned directly by calls to [`os.pullEventRaw`](https://tweaked.cc/module/os.html#v:pullEventRaw) performed by `f`. `terminate` is a valid event for the purposes of this function. If the delivered event matches the active filter, this resumes the coroutine.
- `isDead()`: returns `true` if the coroutine is dead.

If the coroutine errors, `pushEvent` forwards the error. If the coroutine completes (either by `return` or by throwing an error), further calls to `pushEvents` become no-ops. This condition can be detected with `isDead`.

Here's an example of running a coroutine while rewriting and skipping certain events:

```lua
local redirected = redirect.runWithEventSource(f)

while not redirected.isDead() do
	local ev = table.pack(os.pullEventRaw())
	if ev[1] == "a" then
		-- Rewrite
		ev[1] = "b"
	elseif ev[1] == "c" then
		-- Skip
		ev = nil
	end
	if ev then
		-- While `pullEventRaw` might take time, the coroutine cannot become dead between the check
		-- in the `while` condition and this `pushEvent` because it's not resumed by anyone else.
		redirected.pushEvent(table.unpack(ev, 1, ev.n))
	end
end
```
