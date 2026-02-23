def huffman_encode(data: list[int], alphabet: int) -> tuple[bytes, object, int]:
    counts = [0] * alphabet
    for c in data:
        counts[c] += 1

    queue = [(c, count) for c, count in enumerate(counts) if count > 0] # (node, count)
    internal_nodes = []
    while len(queue) > 1:
        i, (node1, count1) = min(enumerate(queue), key = lambda pair: queue[pair[0]][1])
        del queue[i]
        i, (node2, count2) = min(enumerate(queue), key = lambda pair: queue[pair[0]][1])
        del queue[i]
        internal_nodes.append((node1, node2))
        queue.append((-len(internal_nodes), count1 + count2))
    root = queue[0][0]

    bit_lengths = [0] * alphabet
    def dfs(node, height):
        if node >= 0:
            bit_lengths[node] = height
        else:
            child1, child2 = internal_nodes[-node - 1]
            dfs(child1, height + 1)
            dfs(child2, height + 1)
    dfs(root, 0)

    # Heuristic code length limitation algorithm from
    # https://cbloomrants.blogspot.com/2010/07/07-03-10-length-limitted-huffman-codes.html
    length_limit = 25
    if max(bit_lengths) > length_limit:
        bit_lengths = [min(bit_len, length_limit) for bit_len in bit_lengths]
        kraft = sum(2 ** (length_limit - bit_len) for bit_len in bit_lengths if bit_len > 0)

        symbols = sorted((c for c, count in enumerate(counts) if count > 0), key = lambda c: counts[c])
        for c in symbols:
            while bit_lengths[c] < length_limit and kraft > 2 ** length_limit:
                bit_lengths[c] += 1
                kraft -= 2 ** (length_limit - bit_lengths[c])
        for c in symbols[::-1]:
            while kraft + 2 ** (length_limit - bit_lengths[c]) <= 2 ** length_limit:
                kraft += 2 ** (length_limit - bit_lengths[c])
                bit_lengths[c] -= 1

        assert kraft == 2 ** length_limit
        assert max(bit_lengths) <= length_limit

    symbols = sorted(
        (c for c, count in enumerate(counts) if count > 0),
        key = lambda ch: (bit_lengths[ch], ch),
    )
    encoding = [None] * alphabet
    encoding[symbols[0]] = 0
    counter = 0
    for prev, cur in zip(symbols, symbols[1:]):
        counter = (counter + 1) << (bit_lengths[cur] - bit_lengths[prev])
        encoding[cur] = counter

    out = bytearray()
    bits = 0
    bit_len = 0
    total_bit_len = 0
    for c in data:
        bits = (bits << bit_lengths[c]) | encoding[c]
        bit_len += bit_lengths[c]
        total_bit_len += bit_lengths[c]
        while bit_len >= 8:
            out.append(bits >> (bit_len - 8))
            bit_len -= 8
            bits &= (1 << bit_len) - 1
    if bit_len > 0:
        out.append(bits << (8 - bit_len))

    root = [None, None]
    for c, (bit_len, enc) in enumerate(zip(bit_lengths, encoding)):
        if bit_len == 0:
            continue
        ptr = root
        for i in range(bit_len - 1, -1, -1):
            bit = (enc >> i) & 1
            if i == 0:
                ptr[bit] = c
            else:
                if not ptr[bit]:
                    ptr[bit] = [None, None]
                ptr = ptr[bit]

    return bytes(out), root, total_bit_len
