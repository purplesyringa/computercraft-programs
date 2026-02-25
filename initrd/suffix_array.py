def suffix_array(data: bytes) -> list[int]:
    n = len(data)

    counts = [0] * max(256, n)
    for cl in data:
        counts[cl] += 1
    for cl in range(1, 256):
        counts[cl] += counts[cl - 1]
    permutation = [0] * n
    for i, cl in enumerate(data):
        counts[cl] -= 1
        permutation[counts[cl]] = i

    class_of_shift = [0] * n
    pointers = [0]
    prev_key = None
    for cur in permutation:
        cur_key = data[cur]
        if cur_key != prev_key:
            pointers.append(pointers[-1])
        pointers[-1] += 1
        class_of_shift[cur] = len(pointers) - 2
        prev_key = cur_key

    sorted_len = 1
    while sorted_len < n:
        for start in permutation[:]:
            start = (start - sorted_len) % n
            cl = class_of_shift[start]
            permutation[pointers[cl]] = start
            pointers[cl] += 1

        new_class_of_shift = [0] * n
        pointers = [0]
        prev_key = None
        finished = True
        for cur in permutation:
            cur_key = class_of_shift[cur], class_of_shift[(cur + sorted_len) % n]
            if cur_key == prev_key:
                finished = False
            else:
                pointers.append(pointers[-1])
            pointers[-1] += 1
            new_class_of_shift[cur] = len(pointers) - 2
            prev_key = cur_key
        class_of_shift = new_class_of_shift

        if finished:
            break

        sorted_len *= 2

    return permutation
