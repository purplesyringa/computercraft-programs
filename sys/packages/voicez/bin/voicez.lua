local vfs = require "vfs"
local voicez = require "voicez"

local args = { ... }
if #args ~= 2 then
    print("Usage: voicez <input.dfpwm> <output.voicez>")
    print("       unvoicez <input.voicez> <output.dfpwm>")
    return
end

local input = vfs.read(shell.resolve(args[1]))
local output = voicez.encode(input)
vfs.write(shell.resolve(args[2]), output)
