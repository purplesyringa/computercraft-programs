use initrd_core::prelude::*;
use std::{io::Result, path::Path};

fn build_tree(path: &Path) -> Result<LuaValue> {
    let meta = path.metadata()?;
    let mut node = LuaTable::new();
    if meta.is_dir() {
        let mut entries = LuaTable::new();
        for dir_entry in std::fs::read_dir(path)? {
            let dir_entry = dir_entry?;
            if dir_entry.metadata()?.is_dir() && dir_entry.path().join(".rdignore").try_exists()? {
                continue;
            }
            assert!(
                dir_entry.file_name().is_ascii(),
                "Non-ASCII filenames are unsupported: {:?}",
                dir_entry.file_name()
            );
            let file_name = dir_entry
                .file_name()
                .to_str()
                .unwrap()
                .as_bytes()
                .to_owned();
            entries.insert(file_name.into(), build_tree(&dir_entry.path())?);
        }
        node.insert(b"entries".into(), entries.into());
    } else if meta.is_file() {
        node.insert(
            b"contents".into(),
            LuaString::from(std::fs::read(path)?).into(),
        );
    } else {
        panic!("Unknown file type {:?} at {path:?}", meta.file_type());
    }
    Ok(node.into())
}

pub fn build_uncompressed_initrd(sysroot: &Path) -> Vec<u8> {
    let tree = build_tree(sysroot).unwrap();
    initrd_core::templates::substitute_template(
        include_bytes!("initrd-template.lua"),
        [("__TREE__", &serialize_to_vec(&tree)[..])].into(),
    )
}
