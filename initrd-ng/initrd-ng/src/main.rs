use argh::FromArgs;
use std::path::{Path, PathBuf};

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

fn make_initrd(tree: &fs::Entry, uncompressed: bool, ignore_path: Option<&Path>) -> Vec<u8> {
    let initrd = fs::build_uncompressed_initrd(tree, ignore_path);
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
            std::fs::write(ba.output, make_initrd(&tree, ba.uncompressed, None)).unwrap();
        }

        Command::Analyze(aa) => {
            assert!(aa.dir.as_os_str().is_ascii(), "non-ascii dir name?");
            let mut tree = fs::build_tree(&aa.sysroot).unwrap();

            let total = make_initrd(&tree, false, None).len().cast_signed();
            println!("{total}\t100.0\t<initrd>");

            let mut sizes = Vec::<(isize, String)>::new();
            let names = tree
                .walk_to(&aa.dir)
                .expect("no such directory")
                .iter()
                .map(|(name, entry)| format!("{name}{}", if entry.is_dir() { "/" } else { "" }))
                .collect::<Vec<_>>();

            for name in names {
                let path = aa.dir.join(&name);
                let size = make_initrd(&tree, false, Some(&path)).len().cast_signed();
                sizes.push((size, name));
            }

            let size = make_initrd(&tree, false, Some(&aa.dir)).len().cast_signed();
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
