use argh::FromArgs;
use std::path::PathBuf;

mod bz;
mod fs;
mod huffman;
mod snippets;

#[derive(FromArgs)]
/// initrd generator and analyzer
struct Args {
    #[argh(subcommand)]
    command: Command,
}

#[derive(FromArgs)]
#[argh(subcommand)]
enum Command {
    Build(BuildArgs),
}

#[derive(FromArgs)]
/// build the initrd
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

fn make_initrd(tree: &fs::Entry, uncompressed: bool) -> Vec<u8> {
    let initrd = fs::build_uncompressed_initrd(tree);
    if uncompressed {
        initrd
    } else {
        let (data, tree, total_bit_len, shift) = bz::compress(&initrd);
        snippets::generate_sfx(&data, tree, total_bit_len, shift)
    }
}

fn main() {
    let args: Args = argh::from_env();

    match args.command {
        Command::Build(ba) => {
            let tree = fs::build_tree(&ba.sysroot).unwrap();
            std::fs::write(ba.output, make_initrd(&tree, ba.uncompressed)).unwrap();
        }
    }
}
