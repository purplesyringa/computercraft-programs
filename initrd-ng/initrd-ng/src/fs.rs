use initrd_core::prelude::*;
use std::{collections::HashMap, io::Result, path::Path};

enum Entry {
    File(Vec<u8>),
    Dir(HashMap<String, Entry>),
}

fn build_tree(path: &Path) -> Result<Entry> {
    let meta = path.metadata()?;
    if meta.is_dir() {
        let mut entries = HashMap::new();
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
            let file_name = dir_entry.file_name().to_str().unwrap().to_owned();
            entries.insert(file_name, build_tree(&dir_entry.path())?);
        }
        Ok(Entry::Dir(entries))
    } else if meta.is_file() {
        Ok(Entry::File(std::fs::read(path)?))
    } else {
        panic!("Unknown file type {:?} at {path:?}", meta.file_type());
    }
}

fn to_lua_tree(tree: Entry) -> LuaValue {
    let mut node = LuaTable::new();
    match tree {
        Entry::File(contents) => {
            node.insert(b"contents".into(), LuaString::from(contents).into());
        }
        Entry::Dir(entries) => {
            let lua_entries = entries
                .into_iter()
                .map(|(name, entry)| (name.into_bytes().into(), to_lua_tree(entry)))
                .collect::<LuaTable>();
            node.insert(b"entries".into(), lua_entries.into());
        }
    }
    node.into()
}

pub fn build_uncompressed_initrd(sysroot: &Path) -> Vec<u8> {
    let tree = to_lua_tree(build_tree(sysroot).unwrap());
    initrd_core::templates::substitute_template(
        include_bytes!("initrd-template.lua"),
        [("__TREE__", &serialize_to_vec(&tree)[..])].into(),
    )
}
