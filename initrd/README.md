# initrd

This directory contains the code to build a bootable `initrd.lua` image from the [`sys`](../sys) directory.

## Usage

Run `python3 -m initrd <output.lua>` from the root of the repository. If you need to rebuild the image constantly, you can use PyPy for a small speedup, but unless you're debugging initrd itself, you should most likely just symlink or bind-mount `sys` into the computer's filesystem in your local Minecraft instance.

## Design

The generated `initrd.lua` file is fundamentally "just" a bzip-encoded blob with an inline decoder that unbzips the data and executes it as code. The compressed code contains a table literal describing the contents of the [`sys`](../sys) directory in the [`tmpfs`](../sys/packages/tmpfs) format, as well as the [`vfs`](../sys/packages/vfs) and [`tmpfs`](../sys/packages/vfs) drivers needed to mount it, and passes control to `sys/startup.lua`. Nothing tricky here.

The less obvious part is the choice of a custom (!) bzip-like format as opposed to, say, [Luz](https://github.com/MCJack123/Luz), [LibDeflate](https://github.com/SafeteeWoW/LibDeflate/blob/main/LibDeflate.lua), or bzip itself. There are multiple reasons for this:

1. Since the image needs to be self-contained, the size of the decoder matters. Encoding metadata as Lua literals is thus almost always better than compressing it optimally and then wasting space to decode it. This calls for a custom format.

2. The plan is that `initrd.lua` should fit on a 125 KB floppy disk. We're about halfway there, and when we'll get close to that boundary, it's better to use a compressor that can implement the required compression ratio. bzip compresses text better than any other popular format (zstd included), so it has the best chance.

3. bzip has a really simple pipeline. [BWT](https://en.wikipedia.org/wiki/Burrows–Wheeler_transform) is the sole non-trivial part, and even though it's non-trivial to encode, decoding takes just a few lines of code. We might eventually have to complicate the format to improve the compression ratio further, but these improvements would require just as much code with other formats.

4. The only good reason not to use bzip is speed. LibDeflate is about twice as fast, and Luz is even faster because it operates on tokens (but has a larger decoder). But computers boot rarely, and since `initrd` compressed with our implementation of bzip boots in 0.3s, it's perfectly acceptable.

On the other extreme of standard formats like DEFLATE are [fine-tuned formats](https://mattmahoney.net/dc/text.html), but they typically require large constant tables, which is a net loss on our scale. This excludes contenders like ZPAQ.

With that out of the way, let's quickly go over the format itself. I recommend reading [the bzip2 format specification](https://github.com/dsnet/compress/blob/master/doc/bzip2-format.pdf) first, since the ad-hoc format is mostly based on it. The main differences are:

1. We always produce a single block and don't emit headers or footers.
2. Our pipeline is BWT + MTF + RLE0 + HUFF, omitting the first RLE step from bzip2, since it's unnecessary on our data.
3. The BWT origin pointer stores `perm[ptr]` as opposed to `ptr`. The encoder uses the standard O(n log n) SACA algorithm since it's easy to write and runs fast enough.
4. RUNA and RUNB are encoded as 0 and 1 respectively, meaning that MTF offsets start at 2: this agrees with Lua's 1-based indexing.
5. The Huffman alphabet excludes EOB, we directly substitute the block length into the decoder code instead.
6. Since the Huffman tree is very asymmetric post-MTF, we JIT it to decode symbols bit-by-bit, which turns out to be faster than using a precomputed table.
7. The bitmap of symbols present in data is not stored explicitly, instead it's stored as part of the Huffman tree.
8. We only use a single Huffman tree without selectors. The tree is substituted into the decoder code instead of being parsed in runtime.

We're currently not matching `bzip2`'s or `bzip3`'s compression ratio, but we're still smaller than every popular format except zstd, but only by ~500 bytes, which is certainly not enough to fit a zstd decoder. The possible incremental improvements are:

1. Apply [LZP](https://hugi.scene.org/online/coding/hugi%2012%20-%20colzp.htm) before BWT like bzip3 does. This would save us about 1% of space, and wouldn't require too much code.
2. Reverse the input. This makes sense because BWT effectively predicts characters backwards, while code is usually easier to predict forwards. This would save us about 0.5%.
3. Replace Huffman with [tANS](https://en.wikipedia.org/wiki/Asymmetric_numeral_systems#Tabled_variant_(tANS)). This would save us about 1% in compressed data, at the cost of embedding more metadata and losing out on JIT.
4. Use multiple Huffman trees. This would save us about 4%, but we'd need to encode trees more optimally instead of just using table literals.
5. Alternatively, use a context-adaptive predictive model. bzip3 saves 12% on bzip2 with this method, but requires decoding data bit-by-bit, significantly slowing down decompression. Adjusting the frequencies only every 50 bytes and using [rANS](https://en.wikipedia.org/wiki/Asymmetric_numeral_systems#Range_variants_(rANS)_and_streaming) might help here, but requires experimentation and may fail to work well due to the 50-byte lag.
