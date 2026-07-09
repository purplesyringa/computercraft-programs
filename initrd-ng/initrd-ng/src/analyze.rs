use crate::fs;
use rayon::prelude::*;
use std::path::Path;

fn initrd_size(tree: &fs::Entry, ignore: Option<&Path>) -> isize {
    fs::make_initrd(tree, false, ignore).len().cast_signed()
}

pub fn analyze(sysroot: &Path, dir: &Path) {
    assert!(dir.as_os_str().is_ascii(), "non-ascii dir name?");
    let tree = fs::build_tree(sysroot).unwrap();

    let names = tree
        .walk_to(dir)
        .expect("no such directory")
        .iter()
        .map(|(name, entry)| format!("{name}{}", if entry.is_dir() { "/" } else { "" }))
        .chain(Some("./".into()))
        .map(|name| (Some(dir.join(&name)), name))
        .collect::<Vec<_>>();

    let (total, mut sizes) = rayon::join(
        || initrd_size(&tree, None),
        || {
            names
                .into_par_iter()
                .map(|(ignore, name)| (initrd_size(&tree, ignore.as_deref()), name))
                .collect::<Vec<(isize, String)>>()
        },
    );
    println!("{total}\t100.0\t<initrd>");

    sizes.sort();
    for (size, name) in sizes {
        let impact = total - size;
        println!(
            "{impact}\t{:.1}\t{name}",
            100. * impact as f64 / total as f64
        );
    }
}
