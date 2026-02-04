while true do
	while not turtle.place() do turtle.dig() end
	local scanner = nil
	while not scanner do scanner = peripheral.wrap("forward") end
	local scanned = scanner.scan("block", 24, "??:turtle")
	for _, coords in pairs(scanned) do
		local is_self = (coords.x == 1 or coords.x == -1) and coords.y == 0 and coords.z == 0
		if not is_self then
			print(coords.x, coords.y, coords.z)
			goto stop
		end
	end
	turtle.dig()
	for x = 1, 22 do
		while not turtle.forward() do turtle.dig() end
	end
end
::stop::
