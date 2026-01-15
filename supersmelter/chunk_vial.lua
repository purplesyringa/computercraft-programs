local util = require("util")

local chunk_vial = {}

function chunk_vial.equip()
	if not turtle.getEquippedLeft() then
		local item = turtle.getItemDetail(13)
		assert(item and item.name == "turtlematic:chunk_vial", "No chunk vial")
		turtle.select(13)
		turtle.equipLeft()
	end
end

function chunk_vial.unequip()
	local item = turtle.getEquippedLeft()
	if item and item.name == "turtlematic:chunk_vial" then
		assert(not turtle.getItemDetail(13), "Cannot unequip chunk vial")
		turtle.select(13)
		turtle.equipLeft()
	end
end

return chunk_vial
