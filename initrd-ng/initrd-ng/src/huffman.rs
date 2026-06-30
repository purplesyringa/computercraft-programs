use std::{cmp::Reverse, collections::BinaryHeap};

pub enum Node {
    Leaf(u16),
    Branch(Box<Node>, Box<Node>),
}

struct CompareBy<K, V> {
    key: K,
    value: V,
}

impl<K: PartialEq, V> PartialEq for CompareBy<K, V> {
    fn eq(&self, other: &Self) -> bool {
        self.key == other.key
    }
}

impl<K: Eq, V> Eq for CompareBy<K, V> {}

impl<K: PartialOrd, V> PartialOrd for CompareBy<K, V> {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        self.key.partial_cmp(&other.key)
    }
}

impl<K: Ord, V> Ord for CompareBy<K, V> {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.key.cmp(&other.key)
    }
}

fn build_huffman_tree(counts: &[usize]) -> Box<Node> {
    let mut queue = counts
        .iter()
        .enumerate()
        .filter(|(_, count)| **count > 0)
        .map(|(c, count)| CompareBy {
            key: Reverse((*count, c as isize)),
            value: Box::new(Node::Leaf(c as u16)),
        })
        .collect::<BinaryHeap<_>>();

    let mut counter = -1;
    while queue.len() > 1 {
        let node1 = queue.pop().unwrap();
        let node2 = queue.pop().unwrap();
        queue.push(CompareBy {
            key: Reverse((node1.key.0.0 + node2.key.0.0, counter)),
            value: Box::new(Node::Branch(node1.value, node2.value)),
        });
        counter -= 1;
    }

    queue.pop().unwrap().value
}

#[expect(clippy::boxed_local, reason = "Box<Node> is a recursive type")]
fn dfs(node: Box<Node>, height: usize, bit_lengths: &mut [usize]) {
    match *node {
        Node::Leaf(c) => bit_lengths[c as usize] = height,
        Node::Branch(l, r) => {
            dfs(l, height + 1, bit_lengths);
            dfs(r, height + 1, bit_lengths);
        }
    }
}

// Heuristic code length limitation algorithm from
// https://cbloomrants.blogspot.com/2010/07/07-03-10-length-limitted-huffman-codes.html
fn limit_lengths(counts: &[usize], bit_lengths: &mut [usize], length_limit: usize) {
    if *bit_lengths.iter().max().unwrap() < length_limit {
        return;
    }

    for len in bit_lengths.iter_mut() {
        *len = (*len).min(length_limit);
    }

    let mut kraft = bit_lengths
        .iter()
        .filter(|&&len| len > 0)
        .map(|&len| 1u64 << (length_limit - len))
        .sum::<u64>();

    let mut symbols = (0..counts.len())
        .filter(|&c| counts[c] > 0)
        .collect::<Vec<_>>();
    symbols.sort_by_key(|&c| counts[c]);

    for &c in symbols.iter() {
        while bit_lengths[c] < length_limit && kraft > 1u64 << length_limit {
            bit_lengths[c] += 1;
            kraft -= 1u64 << (length_limit - bit_lengths[c]);
        }
    }

    for &c in symbols.iter().rev() {
        while kraft + (1u64 << (length_limit - bit_lengths[c])) <= 1u64 << length_limit {
            kraft += 1u64 << (length_limit - bit_lengths[c]);
            bit_lengths[c] -= 1;
        }
    }

    assert_eq!(kraft, 1u64 << length_limit);
    assert!(*bit_lengths.iter().max().unwrap() <= length_limit);
}

fn build_canonical_code(bit_lengths: &[usize]) -> Vec<u32> {
    let alphabet = bit_lengths.len();
    let mut symbols = (0..alphabet)
        .filter(|&c| bit_lengths[c] > 0)
        .collect::<Vec<_>>();
    symbols.sort_by_key(|&c| Reverse(bit_lengths[c]));

    let mut encoding = vec![0; alphabet];
    let mut counter = 0u32;
    for c in symbols {
        encoding[c] = counter >> (32 - bit_lengths[c]);
        // Wraps around to zero on the last iteration.
        counter = counter.wrapping_add(1 << (32 - bit_lengths[c]));
    }
    encoding
}

struct BitWriter {
    bytes: Vec<u8>,
    acc_bits: u64,
    acc_len: usize,
}

impl BitWriter {
    fn new() -> Self {
        Self {
            bytes: Vec::new(),
            acc_bits: 0,
            acc_len: 0,
        }
    }

    fn extend(&mut self, word: u32, len: usize) {
        self.acc_bits = (self.acc_bits << len) | word as u64;
        self.acc_len += len;
        if self.acc_len >= 32 {
            self.bytes
                .extend(((self.acc_bits >> (self.acc_len - 32)) as u32).to_be_bytes());
            self.acc_len -= 32;
        }
    }

    fn len(&self) -> usize {
        self.bytes.len() * 8 + self.acc_len
    }

    fn into_vec(mut self) -> Vec<u8> {
        let len = self.bytes.len();
        self.bytes
            .extend(((self.acc_bits << (32 - self.acc_len)) as u32).to_be_bytes());
        self.bytes.truncate(len + self.acc_len.div_ceil(8));
        self.bytes
    }
}

fn encode_stream(data: &[u16], bit_lengths: &[usize], encoding: &[u32]) -> (Vec<u8>, usize) {
    let mut out = BitWriter::new();
    for &c in data {
        out.extend(encoding[c as usize], bit_lengths[c as usize]);
    }
    let total_bit_len = out.len();
    (out.into_vec(), total_bit_len)
}

fn encode_bit_lengths(bit_lengths: &[usize]) -> Vec<u8> {
    let mut stream: Vec<u8> = vec![];
    let mut i = 0;
    while i < bit_lengths.len() {
        // RLE: bottom 5 bits of each byte form the bit length, top 3 bits contain a 1-biased count.
        let mut j = i + 1;
        while bit_lengths.get(j) == bit_lengths.get(i) && j - i < 8 {
            j += 1;
        }
        stream.push((((j - i - 1) << 5) | bit_lengths[i]) as u8);
        i = j;
    }
    stream
}

pub fn huffman_encode(data: &[u16], alphabet: usize) -> (Vec<u8>, Vec<u8>, usize) {
    let mut counts = vec![0; alphabet];
    for &c in data {
        counts[c as usize] += 1;
    }

    let root = build_huffman_tree(&counts);

    let mut bit_lengths = vec![0; alphabet];
    dfs(root, 0, &mut bit_lengths);

    limit_lengths(&counts, &mut bit_lengths, 25);

    let encoding = build_canonical_code(&bit_lengths);

    let (out, total_bit_len) = encode_stream(data, &bit_lengths, &encoding);

    while let Some(0) = bit_lengths.last() {
        bit_lengths.pop();
    }

    (out, encode_bit_lengths(&bit_lengths), total_bit_len)
}
