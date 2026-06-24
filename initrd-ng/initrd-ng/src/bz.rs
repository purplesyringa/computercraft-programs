use crate::huffman::{Node, huffman_encode};
use suffix_array::SuffixArray;

// extern crate cdivsufsort;
// unsafe extern "C" {
//     // `output` can be `input`
//     // `temp` can be NULL
//     // returns -1 or -2 on error, primary index otherwise
//     fn divbwt(input: *const u8, output: *mut u8, temp: *mut u8, len: i32) -> i32;
// }
// fn bwt_encode_broken(mut s: Vec<u8>) -> (Vec<u8>, usize) {
//     if s.is_empty() {
//         return (s, 0);
//     }
//     let len = s.len().try_into().unwrap();
//     // SAFETY: arguments are correct
//     let index = unsafe { divbwt(s.as_ptr(), s.as_mut_ptr(), core::ptr::null_mut(), len) };
//     assert!(index != -1, "divbwt error: Wrong arguments");
//     assert!(index != -2, "divbwt error: Allocation failed");
//     assert!(index >= 1, "divbwt returned non-positive index");
//     let index = index as usize;
//     // s[..(index as usize)].rotate_left(1);
//     // (s, index - 1)
//     (s, index)
// }

fn bwt_encode(s: &[u8]) -> (Vec<u8>, usize) {
    let n = s.len();
    let mut dup: Vec<u8> = vec![];
    dup.extend(s);
    dup.extend(s);
    // Collect the suffix array, dropping suffixes from the second half
    let suf = SuffixArray::new(&dup)
        .into_parts()
        .1
        .into_iter()
        .map(|el| el as usize)
        .filter(|&el| el < n)
        .collect::<Vec<_>>();
    let data = suf.iter().map(|&el| dup[n + el - 1]).collect();
    let start = suf.iter().position(|&el| el == 0).unwrap();
    (data, start)
}

fn mtf_encode(s: &[u8]) -> Vec<u8> {
    let mut cache: [u8; 256] = core::array::from_fn(|i| i as u8);
    let mut out = Vec::with_capacity(s.len());
    for &ch in s {
        let pos = cache.iter().position(|&c| c == ch).unwrap();
        out.push(pos as u8);
        cache[0..=pos].rotate_right(1);
    }
    out
}

fn rle0_encode(s: &[u8]) -> Vec<u16> {
    let mut out = vec![];
    let mut i = 0;
    while i < s.len() {
        if s[i] != 0 {
            out.push(s[i] as u16 + 1);
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

pub fn compress(data: &[u8]) -> (Vec<u8>, Box<Node>, usize, usize) {
    let data = data.iter().rev().copied().collect::<Vec<_>>();
    let (data, shift) = bwt_encode(&data);
    let (mut data, tree, total_bit_len) = huffman_encode(&rle0_encode(&mtf_encode(&data)), 257);
    data.extend(b"\0\0\0");
    (data, tree, total_bit_len, shift)
}

#[cfg(test)]
mod tests {
    use super::*;

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

    #[test]
    fn test_mtf() {
        assert_eq!(mtf_encode(b"abacaba"), [97, 98, 1, 99, 1, 2, 1]);
        assert_eq!(
            mtf_encode(b"transform"),
            [116, 115, 99, 112, 116, 106, 114, 5, 114]
        );
        assert_eq!(
            mtf_encode(b"ssdfgsfgsf"),
            [115, 0, 101, 103, 104, 3, 2, 2, 2, 2]
        );
    }
}
