use argh::FromArgs;
use std::path::PathBuf;

mod analyze;
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
}

fn main() {
    let args: Args = argh::from_env();

    match args.command {
        Command::Build(ba) => {
            let tree = fs::build_tree(&ba.sysroot).unwrap();
            std::fs::write(ba.output, fs::make_initrd(&tree, ba.uncompressed, None)).unwrap();
        }

        Command::Analyze(aa) => {
            analyze::analyze(&aa.sysroot);
        }
    }
}
