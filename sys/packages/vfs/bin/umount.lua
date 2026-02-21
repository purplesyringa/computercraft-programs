local vfs = require "vfs"

local args = { ... }
if #args ~= 1 then
	print("Usage: umount <path>")
	return
end

if not vfs.unmount(args[1]) then
	printError("Not mounted")
end
