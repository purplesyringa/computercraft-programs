local vfs = require("init")

local function tabStop(goal_x)
	local x, y = term.getCursorPos()
	term.setCursorPos(math.max(x + 1, goal_x), y)
end

term.setTextColor(colors.green)
write("Mountpoint")
tabStop(1 + 12)
write("Drive")
tabStop(1 + 12 + 8)
print("Description")

for _, mount in ipairs(vfs.list()) do
	if mount.shadowed then
		term.setTextColor(colors.gray)
	else
		term.setTextColor(colors.white)
	end
	write("/" .. mount.root)
	tabStop(1 + 12)
	write(mount.drive)
	tabStop(1 + 12 + 8)
	print(mount.description)
end
