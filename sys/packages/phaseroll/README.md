# phaseroll

Confuse your friends with the magic of sound propagation.

Minecraft sound is weird: sound volume doesn't only affect its loudness, but also its hearing range. By playing the same audio on two speakers in antiphase at different volumes, we can make it so that the audio is cancelled out near the speaker and is loud farther from it. Cue chaos when trying to figure out where a rickroll is playing from.

Under normal circumstances, such a sound is loudest at 16 blocks away from the source, silent at 32 blocks away from the source, and almost silent (barring low-frequency noise) near the source. The noise becomes noticeable at around 4 block distance.

This program assumes that jukebox volume in music settings is turned up to 100%. The effect gets (much) less prominent with smaller volumes.


## Usage

As a library: `require("phaseroll").play(input, speaker1, speaker2)` plays the given DFPWM byte string (`input`) and its inverse on the given two speakers with different volumes. As a program: `phaseroll <file.dfpwm>` plays the given file and automatically discovers speakers.

Since the effect relies on audio cancelling out exactly, the two speakers must be playing from the exact same position, which can be achieved by equipping a turtle with two speakers. You can use hubs from [UnlimitedPeripheralWorks](https://docs.siredvin.site/UnlimitedPeripheralWorks/) if you need more upgrades on the same turtle, like a mimic gadget or an ender modem.

Note that if your server is somewhat slow, the two audio streams can start with a delay, which negates the effect. If this happens, restarting the program after waiting for sound to stop usually helps.
