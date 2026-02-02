while true do
	while not turtle.place() do turtle.dig() end
	local scanner = nil
	while not scanner do scanner = peripheral.wrap("forward") end
	local scanned = scanner.scan("block", 24, "??:turtle")
	for _, coords in pairs(scanned) do
		print(coords.x, coords.y, coords.z)
		goto stop
	end
	turtle.dig()
	for x = 1, 23 do
		while not turtle.forward() do turtle.dig() end
	end
end
::stop::
