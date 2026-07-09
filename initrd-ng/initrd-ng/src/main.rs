use argh::FromArgs;
use std::path::PathBuf;

mod bz;
mod entropy;
mod fs;
mod snippets;

/// initrd generator and analyzer
#[derive(FromArgs)]
struct Args {
    #[argh(subcommand)]
    command: Command,
}

#[derive(FromArgs)]
#[argh(subcommand)]
enum Command {
    Build(BuildArgs),
    Analyze(AnalyzeArgs),
}

/// build the initrd
#[derive(FromArgs)]
#[argh(subcommand, name = "build")]
struct BuildArgs {
    /// sysroot path (e.g. ../sys)
    #[argh(option)]
    sysroot: PathBuf,
    /// output path (e.g. /tmp/initrd.lua)
    #[argh(option)]
    output: PathBuf,
    /// disable bz compression (produces significantly larger initrd)
    #[argh(switch)]
    uncompressed: bool,
}

/// analyze initrd compression
#[derive(FromArgs)]
#[argh(subcommand, name = "analyze")]
struct AnalyzeArgs {
    /// sysroot path (e.g. ../sys)
    #[argh(option)]
    sysroot: PathBuf,
    /// directory to analyze, relative to sysroot
    #[argh(option, default = "PathBuf::new()")]
    dir: PathBuf,
}

fn make_initrd(tree: &fs::Entry, uncompressed: bool) -> Vec<u8> {
    let initrd = fs::build_uncompressed_initrd(tree);
    if uncompressed {
        initrd
    } else {
        let (data, present_bytes, tables, limit, shift) = bz::compress(&initrd);
        snippets::generate_sfx(&data, &present_bytes, tables, limit, shift)
    }
}

fn main() {
    let args: Args = argh::from_env();

    match args.command {
        Command::Build(ba) => {
            let tree = fs::build_tree(&ba.sysroot).unwrap();
            std::fs::write(ba.output, make_initrd(&tree, ba.uncompressed)).unwrap();
        }

        Command::Analyze(aa) => {
            assert!(aa.dir.as_os_str().is_ascii(), "non-ascii dir name?");
            let mut tree = fs::build_tree(&aa.sysroot).unwrap();

            let total = make_initrd(&tree, false).len().cast_signed();
            println!("{total}\t100.0\t<initrd>");

            let mut sizes = Vec::<(isize, String)>::new();
            let names = tree
                .walk_to(&aa.dir)
                .expect("no such directory")
                .keys()
                .cloned()
                .collect::<Vec<_>>();

            for name in names {
                let entry = tree.walk_to_mut(&aa.dir).unwrap().remove(&name).unwrap();

                let size = make_initrd(&tree, false).len().cast_signed();
                sizes.push((
                    size,
                    format!("{name}{}", if entry.is_dir() { "/" } else { "" }),
                ));

                tree.walk_to_mut(&aa.dir).unwrap().insert(name, entry);
            }

            tree.walk_to_mut(&aa.dir).unwrap().clear();
            let size = make_initrd(&tree, false).len().cast_signed();
            sizes.push((size, "./".into()));

            sizes.sort();
            for (size, name) in sizes {
                let impact = total - size;
                println!(
                    "{impact}\t{:.1}\t{name}",
                    100. * impact as f64 / total as f64
                );
            }
        }
    }
}
