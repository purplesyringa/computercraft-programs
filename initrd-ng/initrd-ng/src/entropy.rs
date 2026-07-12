use std::collections::BinaryHeap;
use std::io::Write;

const N_TABLES: usize = 6;
const PROB_BITS: usize = 14;
const STATE_BITS: usize = 53;
const WORD_BITS: usize = 32;

// Costs are computed as `-log_2(p)` and stored scaled by a factor of `COST_SCALE`, such that
// `max_cost * COST_SCALE + SWITCH_COST < 2^16`.
const COST_SCALE: u16 = 2048;
const SWITCH_COST: u16 = 9 * COST_SCALE;
const DEFAULT_COST: u16 = 8 * COST_SCALE;
const MAX_SYMBOL_COST: u16 = u16::MAX - SWITCH_COST;

// Roughly follows bzip2. Returns (unrealistic) per-table symbol costs.
fn build_initial_costs(counts: &[usize]) -> Vec<[u16; N_TABLES]> {
    let alphabet = counts.len();
    let total_count: usize = counts.iter().sum();

    let mut symbols_by_count = (0..alphabet)
        .map(|c| (counts[c], c))
        .filter(|&(count, _)| count > 0)
        .collect::<BinaryHeap<_>>();

    let mut table_costs = vec![[DEFAULT_COST; N_TABLES]; alphabet];
    #[expect(clippy::needless_range_loop, reason = "false positive")]
    for table_idx in 0..N_TABLES {
        let mut symbols_left = total_count / N_TABLES;
        while symbols_left > 0
            && let Some((count, c)) = symbols_by_count.pop()
        {
            symbols_left = symbols_left.saturating_sub(count);
            table_costs[c][table_idx] = 0;
        }
    }
    table_costs
}

fn calculate_table_choices(data: &[u16], table_costs: &[[u16; N_TABLES]]) -> Vec<[u8; N_TABLES]> {
    #[cfg(target_arch = "x86_64")]
    if std::is_x86_feature_detected!("sse4.1") {
        // SAFETY: sse4.1 is detected
        return unsafe { calculate_table_choices_sse41(data, table_costs) };
    }

    // Locate optimal table switches. `costs[table_idx]` is the cost to encode the current suffix if
    // the active table is `table_idx`, `tables[pos][table_idx]` is the table chosen for encoding of
    // the corresponding position.
    let mut costs = [0; N_TABLES];
    let mut tables = vec![[0; N_TABLES]; data.len() + 1];

    for (pos, &c) in data.iter().enumerate().rev() {
        let base_cost: [_; N_TABLES] = core::array::from_fn(|table_idx| {
            table_costs[c as usize][table_idx] as u32 + costs[table_idx]
        });
        let (best_table_idx, min_base_cost) = base_cost
            .iter()
            .enumerate()
            .min_by_key(|&(_, &cost)| cost)
            .unwrap();

        for table_idx in 0..N_TABLES {
            let same_cost = base_cost[table_idx];
            let switched_cost = min_base_cost + SWITCH_COST as u32;
            (costs[table_idx], tables[pos][table_idx]) = if switched_cost < same_cost {
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
    table_costs: &[[u16; N_TABLES]],
) -> Vec<[u8; N_TABLES]> {
    use core::arch::x86_64::*;

    let mut costs = _mm_setzero_si128(); // biased, non-negative
    let mut tables = vec![[0; N_TABLES]; data.len() + 1];

    let table_costs = table_costs
        .iter()
        .map(|costs| {
            let mut vec_costs = [0; 8];
            vec_costs[..N_TABLES].copy_from_slice(costs);
            unsafe { core::mem::transmute(vec_costs) }
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
        costs = _mm_min_epu16(biased_retain_cost, biased_switched_cost);

        let new_tables = _mm_blendv_epi8(
            _mm_set1_epi16(best_table_idx),
            _mm_set_epi16(7, 6, 5, 4, 3, 2, 1, 0),
            _mm_cmpeq_epi16(costs, biased_retain_cost),
        );
        let new_tables: [u16; 8] = unsafe { core::mem::transmute(new_tables) };
        // Compiles to a shuffle, followed by some combination of `movd` and `pextrb`. Not on
        // a lantecy-critical path, so doesn't matter as much.
        for table_idx in 0..N_TABLES {
            tables[pos][table_idx] = new_tables[table_idx] as u8;
        }
    }

    tables
}

fn calculate_per_table_histograms(
    alphabet: usize,
    data: &[u16],
    tables: &[[u8; N_TABLES]],
) -> [Vec<usize>; N_TABLES] {
    let mut histograms = core::array::from_fn(|_| vec![0; alphabet]);
    let mut active_table_idx = 0;
    for (&c, symbol_tables) in data.iter().zip(tables) {
        let table_idx = symbol_tables[active_table_idx] as usize;
        if active_table_idx != table_idx {
            // Switch table.
            histograms[active_table_idx][alphabet - N_TABLES + table_idx] += 1;
            active_table_idx = table_idx;
        }
        histograms[table_idx][c as usize] += 1;
    }
    histograms
}

fn calculate_symbol_tables(tables: &[[u8; N_TABLES]]) -> Vec<usize> {
    let mut active_table_idx = 0;
    (0..tables.len() - 1)
        .map(|pos| {
            active_table_idx = tables[pos][active_table_idx] as usize;
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

fn recompute_costs(table_costs: &mut [[u16; N_TABLES]], histograms: &[Vec<usize>; N_TABLES]) {
    for (table_idx, histogram) in histograms.iter().enumerate() {
        let total_count = histogram.iter().sum::<usize>();
        for (c, &count) in histogram.iter().enumerate() {
            // log_2(0) = -inf, so absent symbols are correctly treated as having the maximum cost.
            // The cast from `f32` to `u16` is saturating.
            table_costs[c][table_idx] =
                ((COST_SCALE as f32 * -(count as f32 / total_count as f32).log2()) as u16)
                    .min(MAX_SYMBOL_COST);
        }
    }
}

// Returns `Some((symbol_tables, histograms))` on the last stage, `None` otherwise.
#[cfg_attr(feature = "perf-record", inline(never))]
fn refine_approximation(
    counts: &[usize],
    data: &[u16],
    table_costs: &mut [[u16; N_TABLES]],
    is_last_stage: bool,
) -> Option<(Vec<usize>, [Vec<usize>; N_TABLES])> {
    // Find optimal table switches, treating `table_costs` as gospel.
    let dp = calculate_table_choices(data, table_costs);
    let mut histograms = calculate_per_table_histograms(counts.len(), data, &dp);
    if is_last_stage {
        Some((calculate_symbol_tables(&dp), histograms))
    } else {
        apply_zero_frequency_estimator(counts, &mut histograms);
        recompute_costs(table_costs, &histograms);
        None
    }
}

struct EncodingTable {
    probabilities: Vec<u32>,
    cumulative_probabilities: Vec<u32>,

    // ceil(2^64 / probabilities[i]) - 1
    inverse_probabilities: Vec<u64>,
}

impl EncodingTable {
    fn new(counts: &[usize]) -> Self {
        let alphabet = counts.len();
        let mut probabilities = vec![0; alphabet];

        let symbols_by_count = (0..alphabet)
            .map(|c| (counts[c], c))
            .filter(|&(count, _)| count > 0)
            .collect::<BinaryHeap<_>>();

        // Reserve 1 space for each present symbol.
        let free_space: u64 = (1 << PROB_BITS) - symbols_by_count.len() as u64;

        // Allocate the rest of the space greedily to most common symbols first.
        let total_count: usize = counts.iter().sum();
        let mut sum = 0;
        let mut interval_start = 0;
        for (count, c) in symbols_by_count {
            sum += count;
            let interval_end = free_space * sum as u64 / total_count as u64;
            let space = interval_end - interval_start;
            interval_start = interval_end;
            probabilities[c] = space as u32 + 1;
        }

        let mut cumulative_probabilities = Vec::with_capacity(alphabet);
        let mut sum = 0;
        for p in &probabilities {
            cumulative_probabilities.push(sum);
            sum += p;
        }

        let inverse_probabilities = probabilities
            .iter()
            .map(|&p| {
                if p == 0 {
                    0
                } else {
                    ((1u128 << 64).div_ceil(p as u128) - 1) as u64
                }
            })
            .collect();

        Self {
            probabilities,
            cumulative_probabilities,
            inverse_probabilities,
        }
    }

    fn divmod(&self, val: u64, c: usize) -> (u64, u64) {
        // XXX: use widening_mul when stable...
        let (low, high) = self.inverse_probabilities[c].carrying_mul(val, val);
        let rem = (self.probabilities[c] as u64).carrying_mul(low, 0).1;
        (high, rem)
    }
}

struct AnsEncoder {
    words: Vec<u32>,
    state: u64,
}

impl AnsEncoder {
    fn new() -> Self {
        Self {
            words: Vec::new(),
            state: 1 << (STATE_BITS - WORD_BITS),
        }
    }

    #[inline(always)]
    fn dump_word(&mut self) {
        const {
            assert!(WORD_BITS == 32, "assuming 32-bit word");
        }
        self.words.push(self.state as u32);
        self.state >>= WORD_BITS;
    }

    #[inline(always)]
    fn push(&mut self, encoding: &EncodingTable, c: usize) {
        let p = encoding.probabilities[c] as u64;
        if self.state >= p << (STATE_BITS - PROB_BITS) {
            const {
                assert!(WORD_BITS >= PROB_BITS, "too small word length");
            }
            self.dump_word();
        }
        let (div, rem) = encoding.divmod(self.state, c);
        self.state = (div << PROB_BITS) + rem + encoding.cumulative_probabilities[c] as u64;
    }

    fn into_vec(mut self) -> Vec<u8> {
        while self.state > 0 {
            self.dump_word();
        }

        let mut bytes = Vec::with_capacity(self.words.len() * 4);
        for &word in self.words.iter().rev() {
            bytes.extend(word.to_le_bytes());
        }
        bytes
    }
}

fn encode_stream(
    alphabet: usize,
    data: &[u16],
    symbol_tables: &[usize],
    encodings: &[EncodingTable; N_TABLES],
) -> Vec<u8> {
    let mut out = AnsEncoder::new();
    // Push in reverse order for ANS.
    for (i, (&c, &table_idx)) in data.iter().zip(symbol_tables).enumerate().rev() {
        out.push(&encodings[table_idx], c as usize);
        let active_table_idx = if i == 0 { 0 } else { symbol_tables[i - 1] };
        if active_table_idx != table_idx {
            out.push(
                &encodings[active_table_idx],
                alphabet - N_TABLES + table_idx,
            );
        }
    }
    out.into_vec()
}

fn encode_probabilities(probabilities: &[u32]) -> Vec<u8> {
    let mut out: Vec<u8> = vec![];
    let mut i = 0;
    while i < probabilities.len() {
        // RLE0
        let mut j = i;
        while let Some(0) = probabilities.get(j) {
            j += 1;
        }
        if j - i >= 4 {
            // UTF-8 is a reasonably good varint, and Lua has a built-in decoder for it.
            write!(out, "{}", char::from_u32(0x4000 + (j - i) as u32).unwrap()).unwrap();
            i = j;
            continue;
        }
        write!(out, "{}", char::from_u32(probabilities[i]).unwrap()).unwrap();
        i += 1;
    }
    out
}

fn encode_tables(encodings: &[EncodingTable; N_TABLES]) -> Vec<u8> {
    let mut out = Vec::new();
    for table in encodings {
        out.extend(encode_probabilities(&table.probabilities));
        // Add a separator between trees. `encode_bit_lengths` currently never emits 0xFF.
        out.push(0xff);
    }
    out.pop();
    out
}

#[cfg_attr(feature = "perf-record", inline(never))]
pub fn entropy_encode(data: &[u16], alphabet: usize) -> (Vec<u8>, Vec<u8>) {
    let alphabet = alphabet + N_TABLES; // for switching tables

    let mut counts = vec![0; alphabet];
    for &c in data {
        counts[c as usize] += 1;
    }
    // Mark table switching symbols as used so that later passes don't ignore them.
    counts[alphabet - N_TABLES..].fill(1);

    let mut table_costs = build_initial_costs(&counts);

    // Refine the initial approximation.
    let mut out = None;
    for stage_idx in 0..4 {
        let is_last_stage = stage_idx == 3;
        out = refine_approximation(&counts, data, &mut table_costs, is_last_stage);
    }
    let (symbol_tables, histograms) = out.unwrap();

    let encodings = histograms.map(|histogram| EncodingTable::new(&histogram));

    let stream = encode_stream(alphabet, data, &symbol_tables, &encodings);
    let tables = encode_tables(&encodings);

    (stream, tables)
}
