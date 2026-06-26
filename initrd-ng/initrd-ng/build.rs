use initrd_core::prelude::*;
use regex::bytes::Regex;
use std::{path::Path, sync::LazyLock};

fn minify(code: &str) -> Vec<u8> {
    std::process::Command::new("luamin")
        .arg("-c")
        .arg(code)
        .output()
        .expect("luamin error")
        .stdout
        .trim_ascii()
        .into()
}

static DECODE_SYMBOL_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"DECODE_SYMBOL\((?<bits>[^,]+),(?<symbol>[^,]+),(?<bit_pos>[^)]+)\)").unwrap()
});

fn code_template() -> Vec<u8> {
    let decompress = minify(&std::fs::read_to_string("src/decode-stage2.lua").unwrap());
    println!("cargo::rerun-if-changed=src/decode-stage2.lua");

    let captures = DECODE_SYMBOL_REGEX.captures(&decompress).unwrap();
    let bits = captures.name("bits").unwrap().as_bytes();
    let symbol = captures.name("symbol").unwrap().as_bytes();
    let bit_pos = captures.name("bit_pos").unwrap().as_bytes();
    let range = captures.get(0).unwrap().range();

    let decompress1 = LuaString::from(Vec::from(&decompress[..range.start])).into();
    let decompress2 = {
        let mut out = vec![b' ']; // for concatenation with generated code
        out.extend(&decompress[range.end..]);
        LuaString::from(out).into()
    };

    let code = minify(&std::fs::read_to_string("src/decode-stage1.lua").unwrap());
    println!("cargo::rerun-if-changed=src/decode-stage1.lua");

    initrd_core::templates::substitute_template(
        &code,
        [
            ("__SYMBOL__", symbol),
            ("__BIT_POS__", bit_pos),
            ("__BITS__", bits),
            ("__DECOMPRESS1__", &serialize_to_vec(&decompress1)[..]),
            ("__DECOMPRESS2__", &serialize_to_vec(&decompress2)[..]),
        ]
        .into(),
    )
}

fn main() {
    let out_dir = std::env::var_os("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("decompress-template.lua");
    std::fs::write(&dest_path, code_template()).unwrap();
    println!("cargo::rerun-if-changed=build.rs");
}
