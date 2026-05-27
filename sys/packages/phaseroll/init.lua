local function play(input, speaker1, speaker2)
    local pos = 1
    while pos <= #input do
        local buffer_size = 16 * 1024
        local orig_chunk = input:sub(pos, pos + buffer_size - 1)
        pos = pos + buffer_size

        local orig_pcm = {}
        local dual_pcm = {}
        for i = 1, #orig_chunk do
            local byte = orig_chunk:byte(i)
            for j = 0, 7 do
                local bit = bit32.rshift(byte, j) % 2
                table.insert(orig_pcm, -128 + bit * 255)
                table.insert(dual_pcm, 127 - bit * 255)
            end
        end

        while not speaker1.playAudio(orig_pcm) do
            os.pullEvent("speaker_audio_empty")
        end
        while not speaker2.playAudio(dual_pcm, 2) do
            os.pullEvent("speaker_audio_empty")
        end
    end
end

return {
    play = play,
}
