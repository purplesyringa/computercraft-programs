import sys
import struct

byte_stream = sys.stdin.buffer.read()
bits = [(byte >> i) & 1 for byte in byte_stream for i in range(8)]

PRECISION = 8
CTX_LEN = 8

ctx = 0
prob0 = [PRECISION // 2 for _ in range(2 ** CTX_LEN)]

l, r = 0, 0xffffffff

out = bytearray()

prev_bit = 0
for bit in bits:
    enc_bit = bit != prev_bit
    prev_bit = bit

    mid = l + ((r - l) * prob0[ctx]) // PRECISION
    # [l, mid] for 0, [mid + 1, r] for 1, both always non-empty
    if not enc_bit:
        r = mid
    else:
        l = mid + 1
    while (l ^ r) & 0xff000000 == 0:
        out.append(l >> 24)
        l = (l << 8) & 0xffffffff
        r = ((r << 8) & 0xffffffff) | 0xff
    if not enc_bit:
        prob0[ctx] = min(prob0[ctx] + 1, PRECISION - 1)
    else:
        prob0[ctx] = max(prob0[ctx] - 1, 1)
    ctx = ((ctx << 1) | enc_bit) & ((1 << CTX_LEN) - 1)

out.append(l >> 24)
out.append((l >> 16) & 0xff)
out.append((l >> 8) & 0xff)
out.append(l & 0xff)

sys.stdout.buffer.write(b"VOCZ" + struct.pack("<I", len(byte_stream)) + out)
