use initrd_core::prelude::*;
use std::path::Path;

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

fn code_template() -> Vec<u8> {
    let decompress = minify(&std::fs::read_to_string("src/decode-stage2.lua").unwrap());
    println!("cargo::rerun-if-changed=src/decode-stage2.lua");

    let code_regex = lazy_regex::bytes_regex!(
        r"^
        (?<decompress1>.*)
        TABLE_START\(\),
        (?<table1>.*)
        DECODE_SYMBOL\((?<bits>[^,]+),(?<symbol>[^,]+),(?<state>[^)]+)\)
        (?<table2>.*)
        TABLE_END\(\)
        (?<decompress2>.*)
        $"sx
    );

    let captures = code_regex.captures(&decompress).unwrap();
    let decompress1 = captures.name("decompress1").unwrap().as_bytes();
    let table1 = captures.name("table1").unwrap().as_bytes();
    let bits = captures.name("bits").unwrap().as_bytes();
    let symbol = captures.name("symbol").unwrap().as_bytes();
    let state = captures.name("state").unwrap().as_bytes();
    let table2 = captures.name("table2").unwrap().as_bytes();
    let decompress2 = captures.name("decompress2").unwrap().as_bytes();

    let decompress1 = LuaString::from(decompress1).into();
    let table1 = LuaString::from(table1).into();
    let table2 = {
        let mut out = vec![b' ']; // for concatenation with generated code
        out.extend(table2);
        LuaString::from(out).into()
    };
    let decompress2 = LuaString::from(decompress2).into();

    let code = minify(&std::fs::read_to_string("src/decode-stage1.lua").unwrap());
    println!("cargo::rerun-if-changed=src/decode-stage1.lua");

    initrd_core::templates::substitute_template(
        &code,
        [
            ("__SYMBOL__", symbol),
            ("__STATE__", state),
            ("__BITS__", bits),
            ("__TABLE1__", &serialize_to_vec(&table1)[..]),
            ("__TABLE2__", &serialize_to_vec(&table2)[..]),
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
