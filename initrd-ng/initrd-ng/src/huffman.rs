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

// Initial distribution, roughly follows bzip2.
fn build_tree_lens(alphabet: usize, counts: &[usize], data: &[u16]) -> [Vec<usize>; N_TREES] {
    let mut symbols_by_count: Vec<u8> = (0..=u8::MAX).filter(|&c| counts[c as usize] > 0).collect();
    symbols_by_count.sort_by_key(|&c| core::cmp::Reverse(counts[c as usize]));
    let mut symbols_by_count = symbols_by_count.into_iter();
    let mut tree_lens = core::array::from_fn(|_| vec![8; alphabet]);
    for lens in &mut tree_lens {
        let mut symbols_left = data.len() / N_TREES;
        while symbols_left > 0
            && let Some(c) = symbols_by_count.next()
        {
            symbols_left = symbols_left.saturating_sub(counts[c as usize]);
            lens[c as usize] = 0;
        }
    }
    tree_lens
}

fn calculate_suffix_cost(
    data: &[u16],
    tree_lens: &[Vec<usize>; N_TREES],
) -> Vec<[(usize, usize); N_TREES]> {
    let mut dp = vec![[(0, 0); N_TREES]; data.len() + 1];

    for (pos, &c) in data.iter().enumerate().rev() {
        let base_cost: [_; N_TREES] = core::array::from_fn(|tree_idx| {
            tree_lens[tree_idx][c as usize] + dp[pos + 1][tree_idx].0
        });
        let (best_tree_idx, min_base_cost) = base_cost
            .iter()
            .enumerate()
            .min_by_key(|&(_, &cost)| cost)
            .unwrap();

        for tree_idx in 0..N_TREES {
            let same_cost = base_cost[tree_idx];
            let switched_cost = min_base_cost + SWITCH_COST;
            dp[pos][tree_idx] = if switched_cost < same_cost {
                (switched_cost, best_tree_idx)
            } else {
                (same_cost, tree_idx)
            };
        }
    }

    dp
}

fn calculate_tree_counts(
    alphabet: usize,
    data: &[u16],
    tree_indices: &mut Vec<usize>,
    dp: &[[(usize, usize); N_TREES]],
) -> ([Vec<usize>; N_TREES], Vec<(usize, usize)>) {
    let mut tree_counts = core::array::from_fn(|_| vec![0; alphabet]);
    let mut tree_idx = 0;
    let mut switches = vec![];
    tree_indices.clear();
    for (pos, &c) in data.iter().enumerate() {
        let next_tree_idx = dp[pos][tree_idx].1;
        if next_tree_idx != tree_idx {
            // Switch tree.
            tree_counts[tree_idx][alphabet - N_TREES + next_tree_idx] += 1;
            switches.push((tree_idx, next_tree_idx));
            tree_idx = next_tree_idx;
        }
        tree_counts[tree_idx][c as usize] += 1;
        tree_indices.push(tree_idx);
    }
    (tree_counts, switches)
}

fn recompute_tree_lens(
    counts: &[usize],
    tree_lens: &mut [Vec<usize>; N_TREES],
    tree_counts: &mut [Vec<usize>; N_TREES],
    is_last_stage: bool,
) {
    for (lens, tree_counts) in tree_lens.iter_mut().zip(tree_counts) {
        if !is_last_stage {
            for (tree_count, &global_count) in tree_counts.iter_mut().zip(counts) {
                if global_count > 0 {
                    // Baby's first zero-frequency estimator.
                    *tree_count = (*tree_count << 8).max(1);
                }
            }
        }
        lens.fill(0);

        dfs(build_huffman_tree(tree_counts), 0, lens);
        limit_lengths(tree_counts, lens, 25);
    }
}

fn refine_approximation(
    alphabet: usize,
    counts: &[usize],
    data: &[u16],
    tree_lens: &mut [Vec<usize>; N_TREES],
    tree_indices: &mut Vec<usize>,
    is_last_stage: bool,
) {
    // Insert optimal tree switches. `dp[pos][tree_idx]` is the cost to encode the suffix
    // `data[pos..]` starting with active tree `tree_idx`.
    let dp = calculate_suffix_cost(data, tree_lens);

    // Compute actual counts.
    let (mut tree_counts, switches) = calculate_tree_counts(alphabet, data, tree_indices, &dp);

    recompute_tree_lens(counts, tree_lens, &mut tree_counts, is_last_stage);

    // Compute bit length for logging.
    let raw_bit_length: usize = data
        .iter()
        .zip(tree_indices.iter())
        .map(|(&c, &tree_idx)| tree_lens[tree_idx][c as usize])
        .sum();
    let total_switch_cost: usize = switches
        .iter()
        .map(|&(from, to)| tree_lens[from][alphabet - N_TREES + to])
        .sum();

    println!(
        "{} ({} switches, {} bits/switch)",
        (raw_bit_length + total_switch_cost) / 8,
        switches.len(),
        total_switch_cost as f32 / switches.len() as f32
    );
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

fn encode_stream(
    alphabet: usize,
    data: &[u16],
    tree_lens: &[Vec<usize>; N_TREES],
    tree_indices: &[usize],
    encodings: &[Vec<u32>; N_TREES],
) -> (Vec<u8>, usize) {
    let mut out = BitWriter::new();
    let mut push_char = |c: usize, tree_idx: usize| {
        out.extend(encodings[tree_idx][c], tree_lens[tree_idx][c]);
    };

    let mut cur_tree_idx = 0;
    for (&c, &tree_idx) in data.iter().zip(tree_indices) {
        if tree_idx != cur_tree_idx {
            push_char(alphabet - N_TREES + tree_idx, cur_tree_idx);
            cur_tree_idx = tree_idx;
        }
        push_char(c as usize, tree_idx);
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

fn encode_trees(tree_lens: &mut [Vec<usize>; N_TREES]) -> (Vec<u8>, [Vec<u32>; N_TREES]) {
    let encodings = core::array::from_fn(|tree_idx| build_canonical_code(&tree_lens[tree_idx]));

    let mut enc_bit_lengths = vec![];
    for lens in tree_lens {
        while let Some(0) = lens.last() {
            lens.pop();
        }
        if !enc_bit_lengths.is_empty() {
            enc_bit_lengths.push(0xff); // cannot occur in the current encoding
        }
        enc_bit_lengths.extend(encode_bit_lengths(lens));
    }
    (enc_bit_lengths, encodings)
}

const N_TREES: usize = 6;
const SWITCH_COST: usize = 9;

pub fn huffman_encode(data: &[u16], alphabet: usize) -> (Vec<u8>, Vec<u8>, usize) {
    let alphabet: usize = alphabet + N_TREES; // for switching trees

    let mut counts = vec![0; alphabet];
    for &c in data {
        counts[c as usize] += 1;
    }
    for tree_idx in 0..N_TREES {
        // Mark tree switching symbols as used so that later passes don't ignore them.
        counts[alphabet - N_TREES + tree_idx] += 1;
    }

    let mut tree_lens = build_tree_lens(alphabet, &counts, data);

    let mut tree_indices = Vec::with_capacity(data.len());

    // Refine the initial approximation.
    for stage_idx in 0..4 {
        let is_last_stage = stage_idx == 3;

        refine_approximation(
            alphabet,
            &counts,
            data,
            &mut tree_lens,
            &mut tree_indices,
            is_last_stage,
        );
    }

    // let size = -data.iter().map(|&c| ((counts[c as usize] as f32) / data.len() as f32).log2()).sum::<f32>() / 8.0;
    // println!("{size}");

    let (enc_bit_lengths, encodings) = encode_trees(&mut tree_lens);

    let (out, total_bit_len) = encode_stream(alphabet, data, &tree_lens, &tree_indices, &encodings);
    (out, enc_bit_lengths, total_bit_len)
}
