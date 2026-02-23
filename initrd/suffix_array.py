def suffix_array(data: bytes) -> list[int]:
    counts = [0] * max(256, len(data))
    for cl in data:
        counts[cl] += 1
    for cl in range(1, 256):
        counts[cl] += counts[cl - 1]
    permutation = [0] * len(data)
    for i, cl in enumerate(data):
        counts[cl] -= 1
        permutation[counts[cl]] = i

    class_of_shift = [0] * len(data)
    class_of_shift[permutation[0]] = 0
    n_classes = 1
    for prev, cur in zip(permutation, permutation[1:]):
        n_classes += data[cur] != data[prev]
        class_of_shift[cur] = n_classes - 1

    sorted_len = 1
    while sorted_len < len(data):
        new_permutation = [(start - sorted_len) % len(data) for start in permutation]
        counts = [0] * n_classes
        for start in new_permutation:
            counts[class_of_shift[start]] += 1
        for cl in range(1, n_classes):
            counts[cl] += counts[cl - 1]
        for start in new_permutation[::-1]:
            cl = class_of_shift[start]
            counts[cl] -= 1
            permutation[counts[cl]] = start

        new_class_of_shift = [0] * len(data)
        new_class_of_shift[permutation[0]] = 0
        n_classes = 1
        for prev, cur in zip(permutation, permutation[1:]):
            cur_pair = class_of_shift[cur], class_of_shift[(cur + sorted_len) % len(data)]
            prev_pair = class_of_shift[prev], class_of_shift[(prev + sorted_len) % len(data)]
            n_classes += cur_pair != prev_pair
            new_class_of_shift[cur] = n_classes - 1
        class_of_shift = new_class_of_shift

        sorted_len *= 2

    return permutation
