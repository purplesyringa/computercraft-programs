use rayon::prelude::*;
use std::path::Path;

pub fn analyze(sysroot: &Path, dir: &Path) {
    assert!(dir.as_os_str().is_ascii(), "non-ascii dir name?");
    let mut tree = crate::fs::build_tree(sysroot).unwrap();

    let names = tree
        .walk_to(dir)
        .expect("no such directory")
        .iter()
        .map(|(name, entry)| format!("{name}{}", if entry.is_dir() { "/" } else { "" }))
        .chain(Some("./".into()))
        .map(|name| (Some(dir.join(&name)), name))
        .chain(Some((None, "<initrd>".into())))
        .collect::<Vec<_>>();

    let mut sizes = names
        .into_par_iter()
        .map(|(ignore, name)| {
            let ignore = ignore.as_deref();
            let size = crate::fs::make_initrd(&tree, false, ignore)
                .len()
                .cast_signed();
            (size, name)
        })
        .collect::<Vec<(isize, String)>>();

    // XXX: rayon preserves order https://github.com/rayon-rs/rayon/issues/551
    let total = sizes.last().unwrap().0;
    sizes.last_mut().unwrap().0 = 0; // convert "size of" to "size without" for <initrd>

    sizes.sort();
    for (size, name) in sizes {
        let impact = total - size;
        println!(
            "{impact}\t{:.1}\t{name}",
            100. * impact as f64 / total as f64
        );
    }
}
