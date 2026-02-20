local vfs = require("init")

local args = { ... }
if #args ~= 1 then
	print("Usage: vfs/unmount <path>")
	return
end

if not vfs.unmount(args[1]) then
	printError("Not mounted")
end
