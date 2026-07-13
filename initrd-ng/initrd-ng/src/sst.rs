#[repr(align(16), C)]
struct Cache([u8; 256]);

#[cfg_attr(feature = "perf-record", inline(never))]
pub fn mtf_encode(s: &[u8]) -> (Vec<u8>, Vec<bool>, usize) {
    let mut present_bytes = vec![false; 256];
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

    let mut out = Vec::with_capacity(s.len());

    #[cfg(target_arch = "x86_64")]
    if std::is_x86_feature_detected!("ssse3") {
        // SAFETY: ssse3 is detected, `cache` contains every character from `s`.
        unsafe { mtf_encode_ssse3(&mut out, &mut cache, s) };
        return (out, present_bytes, alphabet);
    }

    for &ch in s {
        let pos = cache.0.iter().position(|&c| c == ch).unwrap();
        out.push(pos as u8);
        cache.0[0..=pos].rotate_right(1);
    }
    (out, present_bytes, alphabet)
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
unsafe fn mtf_encode_ssse3(out: &mut Vec<u8>, cache: &mut Cache, s: &[u8]) {
    for &ch in s {
        // SAFETY: passthrough
        out.push(unsafe { mtf_single_ssse3(cache, ch) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mtf() {
        assert_eq!(mtf_encode(b"abacaba").0, [0, 1, 1, 2, 1, 2, 1]);
        assert_eq!(mtf_encode(b"transform").0, [7, 6, 2, 5, 7, 5, 7, 5, 7]);
        assert_eq!(mtf_encode(b"ssdfgsfgsf").0, [3, 0, 1, 2, 3, 3, 2, 2, 2, 2]);
    }
}
