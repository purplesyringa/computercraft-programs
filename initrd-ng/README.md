# initrd-ng

This directory contains the code to build and analyze a bootable `initrd.lua` image from the [`sys`](../sys) directory.

## Usage

Run `cargo run --release -- build --sysroot ../sys --output <output.lua>` from this directory. Note that in development, unless you're debugging `initrd` itself, you can often just symlink or bind-mount `sys` into the computer's filesystem in your local Minecraft instance, without rebuilding `initrd`.

Run `cargo run --release -- analyze --sysroot ../sys --dir <path/to/subdir>` from this directory to see how much bytes you will gain if you drop `<path/to/subdir>` from sysroot.

## Design

The generated `initrd.lua` file is fundamentally "just" a bzip-encoded blob with an inline decoder that unbzips the data and executes it as code. The compressed code contains a table literal describing the contents of the [`sys`](../sys) directory in the [`tmpfs`](../sys/packages/tmpfs) format, as well as the [`vfs`](../sys/packages/vfs) and [`tmpfs`](../sys/packages/vfs) drivers needed to mount it, and passes control to `sys/startup.lua`. Nothing tricky here.

The less obvious part is the choice of a custom (!) bzip-like format as opposed to, say, [Luz](https://github.com/MCJack123/Luz), [LibDeflate](https://github.com/SafeteeWoW/LibDeflate/blob/main/LibDeflate.lua), or bzip itself. There are multiple reasons for this:

1. Since the image needs to be self-contained, the size of the decoder matters. Encoding metadata as Lua literals is thus almost always better than compressing it optimally and then wasting space to decode it. This calls for a custom format.

2. The plan is that `initrd.lua` should fit on a 125 KB floppy disk. We're quite close to the limit, so it's better to use a compressor that can implement the required compression ratio. bzip compresses text better than any other popular format (zstd included), so it has the best chance.

3. bzip has a really simple pipeline. The two non-trivial parts are [BWT](https://en.wikipedia.org/wiki/Burrows–Wheeler_transform) and switching between multiple Huffman trees in runtime, and even though both parts are non-trivial to implement in the encoder, decoding takes just a few lines of code. We might eventually have to complicate the format to improve the compression ratio further, but these improvements would require just as much code with other formats.

4. The only good reason not to use bzip is speed. LibDeflate is about twice as fast, and Luz is even faster because it operates on tokens (but has a larger decoder). But computers boot rarely, and since `initrd` compressed with our implementation of bzip boots in 0.6s, it's perfectly acceptable.

On the other extreme of standard formats like DEFLATE are [fine-tuned formats](https://mattmahoney.net/dc/text.html), but they typically require large constant tables, which is a net loss on our scale. This excludes contenders like ZPAQ.

With that out of the way, let's quickly go over the format itself. I recommend reading [the bzip2 format specification](https://github.com/dsnet/compress/blob/master/doc/bzip2-format.pdf) first, since the ad-hoc format is mostly based on it. The main differences are:

1. We always produce a single block and don't emit headers or footers.
2. Our pipeline is BWT + MTF + RLE0 + HUFF, omitting the first RLE step from bzip2, since it's unnecessary on our data.
3. The BWT origin pointer stores `perm[ptr]` as opposed to `ptr`.
4. RUNA and RUNB are encoded as 0 and 1 respectively, meaning that MTF offsets start at 2: this agrees with Lua's 1-based indexing.
5. We use ANS instead of Huffman.
6. The ANS alphabet excludes EOB, we directly substitute the block length into the decoder code instead.
7. We generate JIT code for a binary search-based rANS decoder, since tANS cannot achieve the desired probability precision in reasonable time/space.
8. Instead of switching between ANS tables every 50 bytes and storing the selectors out-of-stream, we implement table switching with additional symbols in the ANS alphabet.

We're close to matching `bzip2`'s compression ratio, and we're smaller than every other popular format. The possible incremental improvements are:

1. Apply a Lua-specific filter for modeling indentation. Simply removing it saves 3% in compressed data, good enough modeling should be able to save 2%.
2. Replace 6 stored probability distributions with a parametrized distribution. This reduces the stored metadata and makes the codec more responsive to local probability changes, but it's unclear which distributions work best.
3. Use a context-adaptive predictive model. bzip3 saves 6% on bzip2 with this method, but requires decoding data bit-by-bit, significantly slowing down decompression. Adjusting the frequencies only every 50 bytes might help here, but requires experimentation and may fail to work well due to the 50-byte lag.
