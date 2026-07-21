use argh::FromArgs;
use std::path::PathBuf;

mod analyze;
mod bwt;
mod bz;
mod entropy;
mod fs;
mod sst;

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
    Compress(CompressArgs),
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

/// compress any lua file
#[derive(FromArgs)]
#[argh(subcommand, name = "compress")]
struct CompressArgs {
    /// input path (e.g. uncompressed.lua)
    #[argh(option)]
    input: PathBuf,
    /// output path (e.g. initrd.lua)
    #[argh(option)]
    output: PathBuf,
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

        Command::Compress(ca) => {
            std::fs::write(ca.output, bz::compress(&std::fs::read(ca.input).unwrap())).unwrap();
        }
    }
}
