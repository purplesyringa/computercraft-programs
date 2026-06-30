use std::{cmp::Reverse, collections::BinaryHeap};

const N_TREES: usize = 6;
const SWITCH_COST: usize = 9;

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

// Roughly follows bzip2. Returns per-tree arrays of (unrealistic) symbol length approximations.
fn build_initial_distribution(counts: &[usize]) -> [Vec<usize>; N_TREES] {
    let alphabet = counts.len();
    let total_count: usize = counts.iter().sum();

    let mut symbols_by_count = (0..alphabet)
        .map(|c| (counts[c], c))
        .filter(|&(count, _)| count > 0)
        .collect::<BinaryHeap<_>>();

    let mut tree_lens = core::array::from_fn(|_| vec![8; alphabet]);
    for lens in &mut tree_lens {
        let mut symbols_left = total_count / N_TREES;
        while symbols_left > 0
            && let Some((count, c)) = symbols_by_count.pop()
        {
            symbols_left = symbols_left.saturating_sub(count);
            lens[c] = 0;
        }
    }
    tree_lens
}

fn calculate_suffix_cost(
    data: &[u16],
    tree_lens: &[Vec<usize>; N_TREES],
) -> Vec<[(usize, usize); N_TREES]> {
    // Locate optimal tree switches. `dp[pos][tree_idx].0` is the cost to encode the suffix
    // `data[pos..]` if the active tree is `tree_idx`, `dp[pos][tree_idx].1` is the tree chosen
    // for encoding.
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

fn calculate_per_tree_histograms(
    alphabet: usize,
    data: &[u16],
    dp: &[[(usize, usize); N_TREES]],
) -> [Vec<usize>; N_TREES] {
    let mut histograms = core::array::from_fn(|_| vec![0; alphabet]);
    let mut active_tree_idx = 0;
    for (pos, &c) in data.iter().enumerate() {
        let tree_idx = dp[pos][active_tree_idx].1;
        if active_tree_idx != tree_idx {
            // Switch tree.
            histograms[active_tree_idx][alphabet - N_TREES + tree_idx] += 1;
            active_tree_idx = tree_idx;
        }
        histograms[tree_idx][c as usize] += 1;
    }
    histograms
}

fn calculate_symbol_trees(dp: &[[(usize, usize); N_TREES]]) -> Vec<usize> {
    let mut active_tree_idx = 0;
    (0..dp.len() - 1)
        .map(|pos| {
            active_tree_idx = dp[pos][active_tree_idx].1;
            active_tree_idx
        })
        .collect()
}

fn apply_zero_frequency_estimator(global_counts: &[usize], histograms: &mut [Vec<usize>; N_TREES]) {
    for histogram in histograms {
        for (count, &global_count) in histogram.iter_mut().zip(global_counts) {
            if global_count > 0 {
                // Baby's first zero-frequency estimator.
                *count = (*count << 8).max(1);
            }
        }
    }
}

fn recompute_tree_lens(tree_lens: &mut [Vec<usize>; N_TREES], histograms: &[Vec<usize>; N_TREES]) {
    for (lens, histogram) in tree_lens.iter_mut().zip(histograms) {
        lens.fill(0);
        dfs(build_huffman_tree(histogram), 0, lens);
        limit_lengths(histogram, lens, 25);
    }
}

// Returns `Some(symbol_trees)` on the last stage, `None` otherwise.
fn refine_approximation(
    counts: &[usize],
    data: &[u16],
    tree_lens: &mut [Vec<usize>; N_TREES],
    is_last_stage: bool,
) -> Option<Vec<usize>> {
    // Find optimal tree switches, treating `tree_lens` as gospel.
    let dp = calculate_suffix_cost(data, tree_lens);
    let mut histograms = calculate_per_tree_histograms(counts.len(), data, &dp);
    if !is_last_stage {
        // Every stage except the last one needs to make sure symbols absent from trees are treated
        // as expensive, the last stage doesn't care because its output is not used for training.
        apply_zero_frequency_estimator(counts, &mut histograms);
    }
    recompute_tree_lens(tree_lens, &histograms);
    if is_last_stage {
        Some(calculate_symbol_trees(&dp))
    } else {
        None
    }
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
    symbol_trees: &[usize],
    encodings: &[Vec<u32>; N_TREES],
) -> (Vec<u8>, usize) {
    let mut out = BitWriter::new();
    let mut push_char = |c: usize, tree_idx: usize| {
        out.extend(encodings[tree_idx][c], tree_lens[tree_idx][c]);
    };

    let mut active_tree_idx = 0;
    for (&c, &tree_idx) in data.iter().zip(symbol_trees) {
        if active_tree_idx != tree_idx {
            push_char(alphabet - N_TREES + tree_idx, active_tree_idx);
            active_tree_idx = tree_idx;
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

fn encode_trees(tree_lens: &[Vec<usize>; N_TREES]) -> Vec<u8> {
    let mut out = vec![];
    for lens in tree_lens {
        // Strip trailing zeros.
        let mut lens = lens.as_slice();
        while let Some((0, prefix)) = lens.split_last() {
            lens = prefix;
        }
        out.extend(encode_bit_lengths(lens));
        // Add a separator between trees. `encode_bit_lengths` currently never emits 0xFF.
        out.push(0xff);
    }
    out.pop();
    out
}

pub fn huffman_encode(data: &[u16], alphabet: usize) -> (Vec<u8>, Vec<u8>, usize) {
    let alphabet = alphabet + N_TREES; // for switching trees

    let mut counts = vec![0; alphabet];
    for &c in data {
        counts[c as usize] += 1;
    }
    // Mark tree switching symbols as used so that later passes don't ignore them.
    counts[alphabet - N_TREES..].fill(1);

    let mut tree_lens = build_initial_distribution(&counts);

    // Refine the initial approximation.
    let mut symbol_trees = None;
    for stage_idx in 0..4 {
        let is_last_stage = stage_idx == 3;
        symbol_trees = refine_approximation(&counts, data, &mut tree_lens, is_last_stage);
    }
    let symbol_trees = symbol_trees.unwrap();

    let encodings = core::array::from_fn(|tree_idx| build_canonical_code(&tree_lens[tree_idx]));

    let (out, total_bit_len) = encode_stream(alphabet, data, &tree_lens, &symbol_trees, &encodings);
    let enc_bit_lengths = encode_trees(&tree_lens);

    (out, enc_bit_lengths, total_bit_len)
}
