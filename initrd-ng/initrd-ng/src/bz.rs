use crate::bwt::bwt_encode;
use crate::entropy::entropy_encode;
use crate::sst::{SrcOutput, src_encode};
use initrd_core::prelude::*;

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

pub fn compress(data: &[u8]) -> Vec<u8> {
    let limit = data.len();
    let (data, shift) = bwt_encode(data);
    let SrcOutput {
        ranks: data,
        initial: src_cache,
    } = src_encode(&data);
    let data = rle0_encode(&data);
    let (data, tables) = entropy_encode(&data, src_cache.len() + 2); // 1 for RLE0, 1 for terminator

    let lua_data = LuaString::from(data).into();
    let lua_cache = LuaString::from(src_cache).into();
    let lua_tables = LuaString::from(tables).into();
    initrd_core::templates::substitute_template(
        include_bytes!(concat!(env!("OUT_DIR"), "/decompress-template.lua")),
        [
            ("__DATA__", &serialize_to_vec(&lua_data)[..]),
            ("__CACHE__", &serialize_to_vec(&lua_cache)[..]),
            ("__TABLES__", &serialize_to_vec(&lua_tables)[..]),
            ("__LIMIT__", (limit + 1).to_string().as_bytes()),
            ("__SHIFT__", (shift + 1).to_string().as_bytes()),
        ]
        .into(),
    )
}
