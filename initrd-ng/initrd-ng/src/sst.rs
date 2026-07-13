//! Second-stage (post-BWT) transform.

/// Output of [`src_encode`].
#[derive(PartialEq, Eq, Debug)]
pub struct SrcOutput {
    /// The sequence of ranks, grouped by character. Groups are separated by a rank denoting the
    /// first impossible move, equal to the cardinality of the alphabet.
    pub ranks: Vec<u16>,
    /// The initial cache.
    pub initial: Vec<u8>,
}

#[repr(align(16), C)]
struct Cache([u8; 256]);

/// Compute the Sorted Rank Coding transform of a string.
#[cfg_attr(feature = "perf-record", inline(never))]
pub fn src_encode(s: &[u8]) -> SrcOutput {
    let mut present_bytes = [false; 256];
    for &c in s {
        present_bytes[c as usize] = true;
    }
    let mut cache: Cache = Cache([0; 256]);
    let mut alphabet = 0;
    for (c, &is_present) in present_bytes.iter().enumerate() {
        if is_present {
            cache.0[alphabet] = c as u8;
            alphabet += 1;
        }
    }

    let mut sequences = [const { Vec::new() }; 256];

    // SAFETY: contains every character from `s`.
    unsafe { src_core_loop(&mut sequences, &mut cache, s) };

    let initial = cache.0[..alphabet].to_vec();

    let ranks = sequences
        .into_iter()
        .filter(|sequence| !sequence.is_empty())
        .flat_map(|sequence| {
            core::iter::once(alphabet as u16)
                .chain(sequence.into_iter().rev().map(|rank| rank as u16))
        })
        .collect();

    SrcOutput { ranks, initial }
}

/// # Safety
///
/// Each character in `s` must be present in `cache`.
unsafe fn src_core_loop(sequences: &mut [Vec<u8>], cache: &mut Cache, s: &[u8]) {
    #[cfg(target_arch = "x86_64")]
    if std::is_x86_feature_detected!("ssse3") {
        // SAFETY: ssse3 is detected, `cache` contains every character from `s`.
        unsafe { src_core_loop_ssse3(sequences, cache, s) };
        return;
    }

    for &ch in s.iter().rev() {
        let pos = cache.0.iter().position(|&c| c == ch).unwrap();
        sequences[ch as usize].push(pos as u8);
        cache.0[0..=pos].rotate_right(1);
    }
}

/// # Safety
///
/// `ch` must be present in `cache`.
#[inline]
#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "ssse3")]
unsafe fn mtf_single_ssse3(cache: &mut Cache, ch: u8) -> u8 {
    const SHUFFLES: [__m128i; 16] = {
        let mut res = [[0u8; 16]; 16];
        let mut pos = 0;
        while pos < 16 {
            res[pos] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
            res[pos].split_at_mut(pos + 1).0.rotate_right(1);
            pos += 1;
        }
        // SAFETY: known ABI
        unsafe { core::mem::transmute(res) }
    };

    const SHUFFLES_WITH_CARRY: [__m128i; 16] = {
        let mut res = SHUFFLES;
        let mut pos = 0;
        while pos < 16 {
            // SAFETY: known ABI
            unsafe { (&raw mut res[pos]).cast::<u8>().write(0x80) };
            pos += 1;
        }
        res
    };

    use core::arch::x86_64::*;
    let mut p: *mut __m128i = cache.0.as_mut_ptr().cast();
    let ch_broadcast = _mm_set1_epi8(ch.cast_signed());

    let mut chunk = unsafe { p.read() };
    let eq_mask = _mm_movemask_epi8(_mm_cmpeq_epi8(chunk, ch_broadcast));
    if eq_mask != 0 {
        let pos = eq_mask.trailing_zeros() as usize;
        let new_chunk = _mm_shuffle_epi8(chunk, SHUFFLES[pos]);
        unsafe { p.write(new_chunk) };
        return pos as u8;
    }

    let new_chunk = _mm_or_si128(
        _mm_shuffle_epi8(chunk, SHUFFLES_WITH_CARRY[15]),
        _mm_cvtsi32_si128(ch.into()),
    );
    unsafe { p.write(new_chunk) };

    loop {
        let carry = _mm_bsrli_si128(chunk, 15);
        p = unsafe { p.add(1) };

        chunk = unsafe { p.read() };

        let eq_mask = _mm_movemask_epi8(_mm_cmpeq_epi8(chunk, ch_broadcast));
        let pos = (eq_mask | 0x8000).trailing_zeros() as usize;
        let new_chunk = _mm_or_si128(_mm_shuffle_epi8(chunk, SHUFFLES_WITH_CARRY[pos]), carry);
        unsafe { p.write(new_chunk) };

        if eq_mask != 0 {
            let offset = unsafe { p.byte_offset_from_unsigned(cache.0.as_mut_ptr()) };
            return (offset + pos) as u8;
        }
    }
}

/// # Safety
///
/// Each character in `s` must be present in `cache`.
#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "ssse3")]
unsafe fn src_core_loop_ssse3(sequences: &mut [Vec<u8>], cache: &mut Cache, s: &[u8]) {
    for &ch in s.iter().rev() {
        // SAFETY: passthrough
        sequences[ch as usize].push(unsafe { mtf_single_ssse3(cache, ch) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_src() {
        assert_eq!(
            src_encode(b"abacaba"),
            SrcOutput {
                ranks: vec![3, 1, 1, 1, 0, 3, 2, 1, 3, 2],
                initial: b"abc".into(),
            }
        );
        assert_eq!(
            src_encode(b"transform"),
            SrcOutput {
                ranks: vec![8, 6, 8, 4, 8, 2, 8, 6, 8, 5, 8, 5, 5, 8, 6, 8, 7],
                initial: b"transfom".into(),
            }
        );
        assert_eq!(
            src_encode(b"ssdfgsfgsf"),
            SrcOutput {
                ranks: vec![4, 3, 4, 2, 2, 1, 4, 2, 3, 4, 0, 3, 2, 3],
                initial: b"sdfg".into(),
            }
        );
    }
}
