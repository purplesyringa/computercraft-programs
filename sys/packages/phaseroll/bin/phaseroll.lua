local phaseroll = require "phaseroll"
local vfs = require "vfs"

local args = { ... }
if #args ~= 1 and #args ~= 2 then
    print("Usage: phaseroll <audio.dfpwm>")
    return
end

local audio = vfs.read(args[1])

local speakers = {}
for side, info in pairs({
    left = turtle.getEquippedLeft(),
    right = turtle.getEquippedRight(),
}) do
    local speaker = nil
    if info then
        if info.name == "computercraft:speaker" then
            speaker = peripheral.wrap(side)
        elseif info.name:match("^peripheralworks:.*peripheralium_hub$") then
            for _, name in ipairs(peripheral.wrap(side).getNamesRemote()) do
                if name:match("^speaker_") then
                    speaker = peripheral.wrap(name)
                    break
                end
            end
        end
    end
    assert(speaker, "no speaker in " .. side .. " hand")
    speakers[side] = speaker
end

phaseroll.play(audio, speakers.left, speakers.right)
