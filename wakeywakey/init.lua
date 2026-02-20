if coroutine._wakeywakey then
	return coroutine._wakeywakey
end

local queued_events = setmetatable({}, { __mode = "k" }) -- coro -> queue
local sync_cache = setmetatable({}, { __mode = "k" })
local async_cache = setmetatable({}, { __mode = "k" })

local orig_yield = coroutine.yield

coroutine.yield = function(...)
	local filter = ...

	local coro = coroutine.running()
	local events = queued_events[coro]

	while events do
		local event = events[events.head]
		events[events.head] = nil
		events.head = events.head + 1
		if events.head == events.tail then
			queued_events[coro] = nil
			events = nil
		end
		if event[1] == filter or filter == nil or event[1] == "terminate" then
			return table.unpack(event)
		end
	end

	return orig_yield(...)
end

local wakeywakey = {
	toSync = function(f)
		if sync_cache[f] then
			return sync_cache[f]
		end

		local function syncFunc(...)
			local current_coro = coroutine.running()

			-- There might already be queued events for this coroutine, and we want to ignore them
			-- while running async code.
			local events = queued_events[current_coro]
			queued_events[current_coro] = nil
			if not events then
				events = { head = 1, tail = 1 }
			end

			local function queueEvents()
				-- Queue new and old events alike.
				if events.head < events.tail then
					queued_events[current_coro] = events
				end
			end

			local args = table.pack(...)
			local coro = coroutine.create(function()
				return f(table.unpack(args, 1, args.n))
			end)

			local result = table.pack(coroutine.resume(coro))
			if not result[1] then
				queueEvents()
				error(result[2], 0)
			end
			while coroutine.status(coro) ~= "dead" do
				local filter = result[2]
				local event = table.pack(os.pullEventRaw())
				events[events.tail] = event
				events.tail = events.tail + 1
				if event[1] == filter or filter == nil or event[1] == "terminate" then
					result = table.pack(coroutine.resume(coro, table.unpack(event, 1, event.n)))
					if not result[1] then
						queueEvents()
						error(result[2], 0)
					end
				end
			end

			queueEvents()
			return table.unpack(result, 2, result.n)
		end

		sync_cache[f] = syncFunc
		async_cache[syncFunc] = f
		return syncFunc
	end,

	toAsync = function(f)
		return async_cache[f] or f
	end,
}

coroutine._wakeywakey = wakeywakey

return coroutine._wakeywakey
