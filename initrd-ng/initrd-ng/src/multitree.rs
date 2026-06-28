use crate::huffman::*;

const N_TREES: usize = 6;
const SWITCH_COST: usize = 9;

pub fn test(data: &[u16], alphabet: usize) -> (Vec<u8>, Vec<u8>, usize) {
    let alphabet: usize = alphabet + N_TREES; // for switching trees

    let mut counts = vec![0; alphabet];
    for &c in data {
        counts[c as usize] += 1;
    }
    for tree_idx in 0..N_TREES {
        // Mark tree switching symbols as used so that later passes don't ignore them.
        counts[alphabet - N_TREES + tree_idx] += 1;
    }

    // Initial distribution, roughly follows bzip2.
    let mut symbols_by_count: Vec<u8> = (0..=u8::MAX).filter(|&c| counts[c as usize] > 0).collect();
    symbols_by_count.sort_by_key(|&c| core::cmp::Reverse(counts[c as usize]));
    let mut symbols_by_count = symbols_by_count.into_iter();
    let mut tree_lens = vec![vec![8; alphabet]; N_TREES];
    for tree_idx in 0..N_TREES {
        let mut symbols_left = data.len() / N_TREES;
        while symbols_left > 0
            && let Some(c) = symbols_by_count.next()
        {
            symbols_left = symbols_left.saturating_sub(counts[c as usize]);
            tree_lens[tree_idx][c as usize] = 0;
        }
    }

    // Refine the initial approximation.
    for stage_idx in 0..4 {
        let is_last_stage = stage_idx == 3;

        // Insert optimal tree switches. `dp[pos][tree_idx]` is the cost to encode the suffix
        // `data[pos..]` starting with active tree `tree_idx`.
        let mut dp = vec![[0; N_TREES]; data.len() + 1];
        for (pos, &c) in data.iter().enumerate().rev() {
            let base_cost: [usize; N_TREES] = core::array::from_fn(|tree_idx| {
                tree_lens[tree_idx][c as usize] + dp[pos + 1][tree_idx]
            });
            let min_base_cost = base_cost.iter().min().unwrap();
            for tree_idx in 0..N_TREES {
                dp[pos][tree_idx] = base_cost[tree_idx].min(min_base_cost + SWITCH_COST);
            }
        }

        // Compute actual counts.
        let mut tree_counts = vec![vec![0; alphabet]; N_TREES];
        let mut cur_tree_idx = 0;
        let mut switches = vec![];
        let mut tree_indices = Vec::with_capacity(data.len());
        for (pos, &c) in data.iter().enumerate() {
            let base_cost: [usize; N_TREES] = core::array::from_fn(|tree_idx| {
                tree_lens[tree_idx][c as usize] + dp[pos + 1][tree_idx]
            });
            if dp[pos][cur_tree_idx] != base_cost[cur_tree_idx] {
                // Switch tree.
                let next_tree_idx = (0..N_TREES)
                    .min_by_key(|&tree_idx| base_cost[tree_idx])
                    .unwrap();
                tree_counts[cur_tree_idx][alphabet - N_TREES + next_tree_idx] += 1;
                switches.push((cur_tree_idx, next_tree_idx));
                cur_tree_idx = next_tree_idx;
            }
            tree_counts[cur_tree_idx][c as usize] += 1;
            tree_indices.push(cur_tree_idx);
        }

        // Recompute tree lengths.
        for (lens, tree_counts) in tree_lens.iter_mut().zip(&mut tree_counts) {
            if !is_last_stage {
                for (tree_count, &global_count) in tree_counts.iter_mut().zip(&counts) {
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

        // Compute bit length for logging.
        let raw_bit_length: usize = data
            .iter()
            .zip(&tree_indices)
            .map(|(&c, &tree_idx)| tree_lens[tree_idx][c as usize])
            .sum();
        let total_switch_cost: usize = switches
            .iter()
            .map(|&(from, to)| tree_lens[from][alphabet - N_TREES + to])
            .sum();

        println!(
            "{stage_idx}: {} ({} switches, {} bits/switch)",
            (raw_bit_length + total_switch_cost) / 8,
            switches.len(),
            total_switch_cost as f32 / switches.len() as f32
        );

        if is_last_stage {
            // Encode trees.
            let mut enc_bit_lengths = vec![];
            let mut encodings = vec![];
            for lens in &mut tree_lens {
                encodings.push(build_canonical_code(lens));
                while lens.last() == Some(&0) {
                    lens.pop();
                }
                if !enc_bit_lengths.is_empty() {
                    enc_bit_lengths.push(0xff); // cannot occur in the current encoding
                }
                enc_bit_lengths.extend(encode_bit_lengths(lens));
            }

            // Encode data.
            let (out, total_bit_len) = encode_stream(
                data,
                &tree_indices,
                &tree_lens,
                &encodings,
                alphabet,
                N_TREES,
            );
            return (out, enc_bit_lengths, total_bit_len);
        }
    }

    unreachable!()

    // let size = -data.iter().map(|&c| ((counts[c as usize] as f32) / data.len() as f32).log2()).sum::<f32>() / 8.0;
    // println!("{size}");
}
