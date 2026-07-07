use std::{cmp::Reverse, collections::BinaryHeap};

const N_TABLES: usize = 6;
const SWITCH_COST: u32 = 9;

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

// Roughly follows bzip2. Returns per-table arrays of (unrealistic) symbol length approximations.
fn build_initial_costs(counts: &[usize]) -> [Vec<usize>; N_TABLES] {
    let alphabet = counts.len();
    let total_count: usize = counts.iter().sum();

    let mut symbols_by_count = (0..alphabet)
        .map(|c| (counts[c], c))
        .filter(|&(count, _)| count > 0)
        .collect::<BinaryHeap<_>>();

    let mut table_costs = core::array::from_fn(|_| vec![8; alphabet]);
    for lens in &mut table_costs {
        let mut symbols_left = total_count / N_TABLES;
        while symbols_left > 0
            && let Some((count, c)) = symbols_by_count.pop()
        {
            symbols_left = symbols_left.saturating_sub(count);
            lens[c] = 0;
        }
    }
    table_costs
}

fn calculate_table_choices(
    data: &[u16],
    table_costs: &[Vec<usize>; N_TABLES],
) -> [Vec<u8>; N_TABLES] {
    #[cfg(target_arch = "x86_64")]
    if std::is_x86_feature_detected!("sse4.1") {
        // SAFETY: sse4.1 is detected
        return unsafe { calculate_table_choices_sse41(data, table_costs) };
    }

    // Locate optimal table switches. `costs[table_idx]` is the cost to encode the current suffix if
    // the active table is `table_idx`, `tables[table_idx][pos]` is the table chosen for encoding of
    // the corresponding position.
    let mut costs = [0; N_TABLES];
    let mut tables = core::array::from_fn(|_| vec![0; data.len() + 1]);

    // Transpose `table_costs` for performance.
    let alphabet = table_costs[0].len();
    let table_costs = (0..alphabet)
        .map(|c| {
            let mut lens = [0; N_TABLES];
            for table_idx in 0..N_TABLES {
                lens[table_idx] = table_costs[table_idx][c] as u32;
            }
            lens
        })
        .collect::<Vec<_>>();

    for (pos, &c) in data.iter().enumerate().rev() {
        let base_cost: [_; N_TABLES] =
            core::array::from_fn(|table_idx| table_costs[c as usize][table_idx] + costs[table_idx]);
        let (best_table_idx, min_base_cost) = base_cost
            .iter()
            .enumerate()
            .min_by_key(|&(_, &cost)| cost)
            .unwrap();

        for table_idx in 0..N_TABLES {
            let same_cost = base_cost[table_idx];
            let switched_cost = min_base_cost + SWITCH_COST;
            (costs[table_idx], tables[table_idx][pos]) = if switched_cost < same_cost {
                (switched_cost, best_table_idx as u8)
            } else {
                (same_cost, table_idx as u8)
            };
        }
    }

    tables
}

#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "sse4.1")]
fn calculate_table_choices_sse41(
    data: &[u16],
    table_costs: &[Vec<usize>; N_TABLES],
) -> [Vec<u8>; N_TABLES] {
    use core::arch::x86_64::*;

    let mut costs = _mm_setzero_si128(); // biased, non-negative
    let mut tables = core::array::from_fn(|_| vec![0; data.len() + 1]);

    // Transpose `table_costs` for performance.
    let alphabet = table_costs[0].len();
    let table_costs = (0..alphabet)
        .map(|c| {
            let mut lens = [0; 8];
            for table_idx in 0..N_TABLES {
                lens[table_idx] = table_costs[table_idx][c] as i16;
            }
            unsafe { core::mem::transmute(lens) }
        })
        .collect::<Vec<__m128i>>();

    let absent_mask: __m128i = {
        let mut mask = [0; 8];
        mask[N_TABLES..].fill(u16::MAX);
        unsafe { core::mem::transmute(mask) }
    };

    for (pos, &c) in data.iter().enumerate().rev() {
        let base_cost = _mm_add_epi16(table_costs[c as usize], costs);

        let min = _mm_minpos_epu16(_mm_or_si128(base_cost, absent_mask));
        let min_base_cost = _mm_extract_epi16(min, 0) as i16;
        let best_table_idx = _mm_extract_epi16(min, 1) as i16;

        // Bias stored costs by `-min_base_cost`. This ensures the stored values are non-negative
        // and `phminposuw` compares them correctly as unsigned values.
        let biased_retain_cost = _mm_sub_epi16(base_cost, _mm_set1_epi16(min_base_cost));
        let biased_switched_cost = _mm_set1_epi16(SWITCH_COST as i16);
        costs = _mm_min_epi16(biased_retain_cost, biased_switched_cost);

        let new_tables = _mm_blendv_epi8(
            _mm_set1_epi16(best_table_idx),
            _mm_set_epi16(7, 6, 5, 4, 3, 2, 1, 0),
            _mm_cmpeq_epi16(costs, biased_retain_cost),
        );
        let new_tables: [u16; 8] = unsafe { core::mem::transmute(new_tables) };
        for table_idx in 0..N_TABLES {
            tables[table_idx][pos] = new_tables[table_idx] as u8;
        }
    }

    tables
}

fn calculate_per_table_histograms(
    alphabet: usize,
    data: &[u16],
    tables: &[Vec<u8>; N_TABLES],
) -> [Vec<usize>; N_TABLES] {
    let mut histograms = core::array::from_fn(|_| vec![0; alphabet]);
    let mut active_table_idx = 0;
    for (pos, &c) in data.iter().enumerate() {
        let table_idx = tables[active_table_idx][pos] as usize;
        if active_table_idx != table_idx {
            // Switch table.
            histograms[active_table_idx][alphabet - N_TABLES + table_idx] += 1;
            active_table_idx = table_idx;
        }
        histograms[table_idx][c as usize] += 1;
    }
    histograms
}

fn calculate_symbol_tables(tables: &[Vec<u8>; N_TABLES]) -> Vec<usize> {
    let mut active_table_idx = 0;
    (0..tables[0].len() - 1)
        .map(|pos| {
            active_table_idx = tables[active_table_idx][pos] as usize;
            active_table_idx
        })
        .collect()
}

fn apply_zero_frequency_estimator(
    global_counts: &[usize],
    histograms: &mut [Vec<usize>; N_TABLES],
) {
    for histogram in histograms {
        for (count, &global_count) in histogram.iter_mut().zip(global_counts) {
            if global_count > 0 {
                // Baby's first zero-frequency estimator.
                *count = (*count << 8).max(1);
            }
        }
    }
}

fn recompute_costs(table_costs: &mut [Vec<usize>; N_TABLES], histograms: &[Vec<usize>; N_TABLES]) {
    for (lens, histogram) in table_costs.iter_mut().zip(histograms) {
        lens.fill(0);
        dfs(build_huffman_tree(histogram), 0, lens);
        limit_lengths(histogram, lens, 25);
    }
}

// Returns `Some(symbol_tables)` on the last stage, `None` otherwise.
fn refine_approximation(
    counts: &[usize],
    data: &[u16],
    table_costs: &mut [Vec<usize>; N_TABLES],
    is_last_stage: bool,
) -> Option<Vec<usize>> {
    // Find optimal table switches, treating `table_costs` as gospel.
    let dp = calculate_table_choices(data, table_costs);
    let mut histograms = calculate_per_table_histograms(counts.len(), data, &dp);
    if !is_last_stage {
        // Every stage except the last one needs to make sure symbols absent from tables are treated
        // as expensive, the last stage doesn't care because its output is not used for training.
        apply_zero_frequency_estimator(counts, &mut histograms);
    }
    recompute_costs(table_costs, &histograms);
    if is_last_stage {
        Some(calculate_symbol_tables(&dp))
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
    table_costs: &[Vec<usize>; N_TABLES],
    symbol_tables: &[usize],
    encodings: &[Vec<u32>; N_TABLES],
) -> (Vec<u8>, usize) {
    let mut out = BitWriter::new();
    let mut push_char = |c: usize, table_idx: usize| {
        out.extend(encodings[table_idx][c], table_costs[table_idx][c]);
    };

    let mut active_table_idx = 0;
    for (&c, &table_idx) in data.iter().zip(symbol_tables) {
        if active_table_idx != table_idx {
            push_char(alphabet - N_TABLES + table_idx, active_table_idx);
            active_table_idx = table_idx;
        }
        push_char(c as usize, table_idx);
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

fn encode_tables(table_costs: &[Vec<usize>; N_TABLES]) -> Vec<u8> {
    let mut out = vec![];
    for lens in table_costs {
        // Strip trailing zeros.
        let mut lens = lens.as_slice();
        while let Some((0, prefix)) = lens.split_last() {
            lens = prefix;
        }
        out.extend(encode_bit_lengths(lens));
        // Add a separator between tables. `encode_bit_lengths` currently never emits 0xFF.
        out.push(0xff);
    }
    out.pop();
    out
}

pub fn entropy_encode(data: &[u16], alphabet: usize) -> (Vec<u8>, Vec<u8>, usize) {
    let alphabet = alphabet + N_TABLES; // for switching tables

    let mut counts = vec![0; alphabet];
    for &c in data {
        counts[c as usize] += 1;
    }
    // Mark table switching symbols as used so that later passes don't ignore them.
    counts[alphabet - N_TABLES..].fill(1);

    let mut table_costs = build_initial_costs(&counts);

    // Refine the initial approximation.
    let mut symbol_tables = None;
    for stage_idx in 0..4 {
        let is_last_stage = stage_idx == 3;
        symbol_tables = refine_approximation(&counts, data, &mut table_costs, is_last_stage);
    }
    let symbol_tables = symbol_tables.unwrap();

    let encodings = core::array::from_fn(|table_idx| build_canonical_code(&table_costs[table_idx]));

    let (out, total_bit_len) =
        encode_stream(alphabet, data, &table_costs, &symbol_tables, &encodings);
    let enc_bit_lengths = encode_tables(&table_costs);

    (out, enc_bit_lengths, total_bit_len)
}
