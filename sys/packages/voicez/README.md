# voicez

A voice codec.

voicez is a lossless codec that post-processes DFPWM-encoded voice audio. Since ComputerCraft always re-encodes audio to DFPWM before playing it, this ensures that quality does not fall any further than necessary.

voicez typically reduces the file size by 30% when compressing voice. Since it's tuned for voice specifically, it will most likely increase the file size when encoding music or other non-voice audio.

## Usage

Run `voicez <input.dfpwm> <output.voicez>` to encode audio and `unvoicez <input.voicez> <output.dfpwm>` to decode it. Alternatively, run `voicez.encode(input)` or `voicez.decode(input)` from Lua to convert byte strings. A [reference encoder](codec.py) is also available in Python.

## Design

Since Lua is slow, the codec is designed to be as lightweight as possible while still providing meaningful improvements. At its core is a variant of [CABAC](https://en.wikipedia.org/wiki/Context-adaptive_binary_arithmetic_coding): individual bits (nicely mapping to DFPWM's 1-bit samples) are encoded with a binary arithmetic coder, the probabilities for which are estimated based on the context of the previous 8 samples. The approach favors highly predictable waves, such as near-linear growth and near-silence, both common in isolated audio sources.
