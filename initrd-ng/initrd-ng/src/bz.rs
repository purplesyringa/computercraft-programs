use crate::entropy::entropy_encode;
use crate::sst::{SrcOutput, src_encode};
use libsais::BwtConstruction;

// https://web.archive.org/web/20251112195119/http://e-maxx.ru/algo/duval_algorithm
fn min_cyclic_shift(dup: &[u8], n: usize) -> usize {
    let mut i = 0;
    let mut ans = 0;
    while i < n {
        ans = i;
        let mut j = i + 1;
        let mut k = i;
        while j < 2 * n && dup[k] <= dup[j] {
            if dup[k] < dup[j] {
                k = i;
            } else {
                k += 1;
            }
            j += 1;
        }
        while i <= k {
            i += j - k;
        }
    }
    ans
}

// This originally used Z-function, but this quadratic loop works faster in practice for our data.
fn count_cyclic_shifts_less_than_s(dup: &[u8], n: usize) -> usize {
    (1..n)
        .filter(|i| {
            (0..n)
                .find(|&j| dup[i + j] != dup[j])
                .is_some_and(|j| dup[i + j] < dup[j])
        })
        .count()
}

#[cfg_attr(feature = "perf-record", inline(never))]
fn bwt_encode(s: &[u8]) -> (Vec<u8>, usize) {
    // This implements cyclic-shift-BWT on top of suffix-BWT provided by libsais. We compute the BWT
    // string itself by running suffix-BWT on the lexicographically smallest cyclic shift, which
    // makes it so that comparing suffixes and cyclic shifts produces equivalent results. This
    // corrupts the primary index (it'll always be computed as 0), so we recompute it directly by
    // the definition of a suffix array. This method saves 2x time compared to running SA on `dup`
    // and manually filtering out short suffixes.
    let n = s.len();
    let mut dup = Vec::with_capacity(2 * s.len());
    dup.extend(s);
    dup.extend(s);
    let off = min_cyclic_shift(&dup, n);
    let data = BwtConstruction::for_text(&dup[off..][..n])
        .with_owned_temporary_array_buffer32()
        .single_threaded()
        .run()
        .unwrap()
        .into_vec();
    let start = count_cyclic_shifts_less_than_s(&dup, n);
    (data, start)
}

#[cfg_attr(feature = "perf-record", inline(never))]
fn rle0_encode(s: &[u16]) -> Vec<u16> {
    let mut out = vec![];
    let mut i = 0;
    while i < s.len() {
        if s[i] != 0 {
            out.push(s[i] + 1);
            i += 1;
            continue;
        }
        let mut j = i + 1;
        while j < s.len() && s[j] == 0 {
            j += 1;
        }
        let run_length = j - i;
        let value = run_length + 1;
        // XXX: replace upper bound with `value.bit_width() - 1` on Rust 1.97
        for bit in (0..value.ilog2()).rev() {
            out.push((value >> bit) as u16 & 1);
        }
        i = j;
    }
    out.push(2); // Sentinel to terminate possible sequence of zeros, ignored by decoder
    out
}

pub fn compress(data: &[u8]) -> (Vec<u8>, Vec<u8>, Vec<u8>, usize, usize) {
    let limit = data.len();
    let (data, shift) = bwt_encode(data);
    let SrcOutput {
        ranks: data,
        initial: src_cache,
    } = src_encode(&data);
    let data = rle0_encode(&data);
    let (data, tables) = entropy_encode(&data, src_cache.len() + 2); // 1 for RLE0, 1 for terminator
    (data, src_cache, tables, limit, shift)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_min_cyclic_shift() {
        assert_eq!(min_cyclic_shift(b"abacabaabacaba", 7), 6);
        assert_eq!(min_cyclic_shift(b"transformtransform", 9), 2);
        assert_eq!(min_cyclic_shift(b"ssdfgsfgsfssdfgsfgsf", 10), 2);
        assert_eq!(min_cyclic_shift(b"abababab", 4), 0);
        assert_eq!(min_cyclic_shift(b"cabacaba", 4), 1);
    }

    #[test]
    fn test_bwt() {
        // let (s, i) = bwt_encode_broken(b"abacaba".into());
        let (s, i) = bwt_encode(b"abacaba");
        assert_eq!((String::from_utf8(s), i), (Ok("bcabaaa".into()), 2));
        let (s, i) = bwt_encode(b"transform");
        assert_eq!((String::from_utf8(s), i), (Ok("rsraftonm".into()), 8));
        let (s, i) = bwt_encode(b"ssdfgsfgsf");
        assert_eq!((String::from_utf8(s), i), (Ok("sdssffsggf".into()), 9));
    }
}
