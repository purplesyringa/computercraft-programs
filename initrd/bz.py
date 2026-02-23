from .suffix_array import suffix_array
from .huffman import huffman_encode

# This compression algorithm is basically an adaptation of bzip2. We implement the
# BWT + MTF + RLE0 + HUFF pipeline, the main difference from bzip2 being removing the preprocessing
# RLE step, adjusting the BWT pointer slightly differently, and using a single Huffman tree for the
# entire file..

def bwt_encode(data: bytes) -> tuple[bytes, int]:
    data = data[::-1]
    suf = suffix_array(data)
    return bytes(data[start - 1] for start in suf), suf.index(0)


def mtf_encode(data: bytes) -> bytes:
    byte_cache = bytearray(range(256))
    out = bytearray(len(data))
    for i, c in enumerate(data):
        pos = byte_cache.index(c)
        out[i] = pos
        byte_cache[0], byte_cache[1:pos + 1] = c, byte_cache[:pos]
    return out


def rle_encode(data: bytes) -> list[int]:
    out = []
    i = 0
    while i < len(data):
        if data[i] != 0:
            out.append(data[i] + 1)
            i += 1
            continue
        j = i + 1
        while j < len(data) and data[j] == 0:
            j += 1
        run_length = j - i
        value = run_length + 1
        for bit in range(value.bit_length() - 2, -1, -1):
            out.append((value >> bit) & 1)
        i = j
    return out


def compress(data: bytes) -> tuple[bytes, object, int, int]:
    assert b"\r" not in data, "cannot compress data with CR"
    data, shift = bwt_encode(data)
    data, tree, total_bit_len = huffman_encode(rle_encode(mtf_encode(data)) + [2], 257)
    data += b"\x00\x00\x00"
    return data, tree, total_bit_len, shift
