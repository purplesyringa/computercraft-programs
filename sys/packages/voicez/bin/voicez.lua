local voicez = require "voicez"

local args = { ... }
if #args ~= 2 then
    print("Usage: voicez <input.dfpwm> <output.voicez>")
    print("       unvoicez <input.voicez> <output.dfpwm>")
    return
end

local f, err = fs.open(shell.resolve(args[1]), "r")
if f == nil then
    error(err, 0)
end
local input = f.readAll()
f.close()

local output = voicez.encode(input)

f = fs.open(shell.resolve(args[2]), "w")
if f == nil then
    error(err, 0)
end
f.write(output)
f.close()
