use ignore::WalkBuilder;
use initrd_core::prelude::*;
use std::{
    collections::HashMap,
    path::{Component, Path},
};

pub enum Entry {
    File(Vec<u8>),
    Dir(HashMap<String, Entry>),
}

impl Entry {
    #[expect(unused)]
    pub fn is_file(&self) -> bool {
        matches!(self, Entry::File(_))
    }

    #[expect(unused)]
    pub fn file(&self) -> Option<&[u8]> {
        match self {
            Entry::File(f) => Some(f),
            Entry::Dir(_) => None,
        }
    }

    #[expect(unused)]
    pub fn file_mut(&mut self) -> Option<&mut Vec<u8>> {
        match self {
            Entry::File(f) => Some(f),
            Entry::Dir(_) => None,
        }
    }

    pub fn is_dir(&self) -> bool {
        matches!(self, Entry::Dir(_))
    }

    pub fn dir(&self) -> Option<&HashMap<String, Entry>> {
        match self {
            Entry::File(_) => None,
            Entry::Dir(d) => Some(d),
        }
    }

    pub fn dir_mut(&mut self) -> Option<&mut HashMap<String, Entry>> {
        match self {
            Entry::File(_) => None,
            Entry::Dir(d) => Some(d),
        }
    }

    pub fn walk_to(&mut self, dir: &Path) -> Option<&HashMap<String, Entry>> {
        let mut node = self.dir()?;
        for component in dir.components() {
            let name = match component {
                Component::Normal(name) => name.to_str().unwrap(),
                Component::CurDir => continue,
                Component::RootDir => continue, // can only occur at the first iteration
                _ => panic!("unsupported path component {component:?}"),
            };
            node = node.get(name)?.dir()?;
        }
        Some(node)
    }

    pub fn walk_to_mut(&mut self, dir: &Path) -> Option<&mut HashMap<String, Entry>> {
        let mut node = self.dir_mut()?;
        for component in dir.components() {
            let name = match component {
                Component::Normal(name) => name.to_str().unwrap(),
                Component::CurDir => continue,
                Component::RootDir => continue, // can only occur at the first iteration
                _ => panic!("unsupported path component {component:?}"),
            };
            node = node.get_mut(name)?.dir_mut()?;
        }
        Some(node)
    }
}

pub fn build_tree(root: &Path) -> Result<Entry, ignore::Error> {
    let mut tree = Entry::Dir(HashMap::new());
    for result in WalkBuilder::new(root)
        .add_custom_ignore_filename(".rdignore")
        .hidden(true)
        .build()
    {
        let entry = result?;
        if let Some(error) = entry.error() {
            return Err(error.clone());
        }

        let file_type = entry.file_type().unwrap();
        let full_path = entry.into_path();
        let path = full_path.strip_prefix(root).unwrap();
        // XXX: replace with `path.is_empty()` on Rust 1.98
        if path.as_os_str().is_empty() {
            continue;
        }
        assert!(path.as_os_str().is_ascii(), "non-ascii filename: {path:?}");

        let new_entry = if file_type.is_dir() {
            Entry::Dir(HashMap::new())
        } else if file_type.is_file() {
            Entry::File(std::fs::read(&full_path)?)
        } else {
            panic!("Unknown file type {:?} at {path:?}", file_type);
        };

        // This walk could have been an e-mail, if only `ignore` provided the events
        let entries = tree.walk_to_mut(path.parent().unwrap()).unwrap();
        let name = path.file_name().unwrap().to_str().unwrap();
        let prev = entries.insert(name.into(), new_entry);
        assert!(prev.is_none());
    }
    Ok(tree)
}

fn to_lua_tree(tree: &Entry) -> LuaValue<'_> {
    let mut node = LuaTable::new();
    match tree {
        Entry::File(contents) => {
            node.insert(b"contents".into(), LuaString::Borrowed(contents).into());
        }
        Entry::Dir(entries) => {
            let lua_entries = entries
                .iter()
                .map(|(name, entry)| (name.as_bytes().into(), to_lua_tree(entry)))
                .collect::<LuaTable>();
            node.insert(b"entries".into(), lua_entries.into());
        }
    }
    node.into()
}

pub fn build_uncompressed_initrd(sysroot_tree: &Entry) -> Vec<u8> {
    let tree = to_lua_tree(sysroot_tree);
    initrd_core::templates::substitute_template(
        include_bytes!("initrd-template.lua"),
        [("__TREE__", &serialize_to_vec(&tree)[..])].into(),
    )
}
