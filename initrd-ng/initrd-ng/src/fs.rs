use ignore::WalkBuilder;
use initrd_core::prelude::*;
use std::{
    collections::HashMap,
    path::{Component, Path},
};

fn lexical_components(path: &Path) -> impl Iterator<Item = &str> {
    path.components().filter_map(|comp| match comp {
        Component::Normal(name) => Some(name.to_str().unwrap()),
        Component::CurDir => None,
        Component::RootDir => None, // can only occur at the first iteration
        _ => panic!("unsupported path component {comp:?}"),
    })
}

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

    pub fn walk_to(&self, dir: &Path) -> Option<&HashMap<String, Entry>> {
        let mut node = self.dir()?;
        for name in lexical_components(dir) {
            node = node.get(name)?.dir()?;
        }
        Some(node)
    }

    pub fn walk_to_mut(&mut self, dir: &Path) -> Option<&mut HashMap<String, Entry>> {
        let mut node = self.dir_mut()?;
        for name in lexical_components(dir) {
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

fn to_lua_tree<'tree>(tree: &'tree Entry, ignore: Option<&[&str]>) -> Option<LuaValue<'tree>> {
    if let Some([]) = ignore {
        return None;
    }
    let mut node = LuaTable::new();
    match tree {
        Entry::File(contents) => {
            node.insert(b"contents".into(), LuaString::Borrowed(contents).into());
        }
        Entry::Dir(entries) => {
            let mut lua_entries = LuaTable::with_capacity(entries.len());
            for (name, entry) in entries {
                let next_ignore = match ignore {
                    Some([ignore_name, rest @ ..]) if ignore_name == name => Some(rest),
                    _ => None,
                };
                let lua_name = name.as_bytes().into();
                if let Some(lua_tree) = to_lua_tree(entry, next_ignore) {
                    assert!(lua_entries.insert(lua_name, lua_tree).is_none());
                }
            }
            node.insert(b"entries".into(), lua_entries.into());
        }
    }
    Some(node.into())
}

fn build_uncompressed_initrd(sysroot_tree: &Entry, ignore_path: Option<&Path>) -> Vec<u8> {
    let empty = Entry::Dir(HashMap::new());
    let ignore = ignore_path.map(|p| lexical_components(p).collect::<Vec<_>>());
    let tree = to_lua_tree(sysroot_tree, ignore.as_deref()).unwrap_or_else(|| {
        // Special-case for root directory, as it would otherwise appear as having no impact
        to_lua_tree(&empty, None).unwrap()
    });
    initrd_core::templates::substitute_template(
        include_bytes!("initrd-template.lua"),
        [("__TREE__", &serialize_to_vec(&tree)[..])].into(),
    )
}

pub fn make_initrd(tree: &Entry, uncompressed: bool, ignore_path: Option<&Path>) -> Vec<u8> {
    let initrd = build_uncompressed_initrd(tree, ignore_path);
    if uncompressed {
        initrd
    } else {
        #[cfg(feature = "perf-record")]
        for _ in 1..1000 {
            let (data, present_bytes, tables, limit, shift) = crate::bz::compress(&initrd);
            crate::snippets::generate_sfx(&data, &present_bytes, tables, limit, shift);
        }
        let (data, present_bytes, tables, limit, shift) = crate::bz::compress(&initrd);
        crate::snippets::generate_sfx(&data, &present_bytes, tables, limit, shift)
    }
}
