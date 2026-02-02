while true do
	for slot = 1, 16 do
		turtle.select(slot)
		turtle.refuel()
	end
end
