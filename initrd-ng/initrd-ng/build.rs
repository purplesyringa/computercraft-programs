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
    let decompress = LuaString::from(&decompress).into();

    let code = minify(&std::fs::read_to_string("src/decode-stage1.lua").unwrap());
    println!("cargo::rerun-if-changed=src/decode-stage1.lua");

    initrd_core::templates::substitute_template(
        &code,
        [("__DECOMPRESS__", &serialize_to_vec(&decompress)[..])].into(),
    )
}

fn main() {
    let out_dir = std::env::var_os("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("decompress-template.lua");
    std::fs::write(&dest_path, code_template()).unwrap();
    println!("cargo::rerun-if-changed=build.rs");
}
