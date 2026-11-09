//! Known command-line archive engines. Discovery never executes a program;
//! operations use argument vectors and private staging directories.

use std::path::PathBuf;

pub mod catalog;
mod command;
mod options;
mod process;
mod run;
mod streams;

pub use options::Options;
pub use run::{start, start_with_options};

#[cfg(test)]
mod tests;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Engine {
    SevenZip,
    Tar,
    BsdTar,
    Gzip,
    Pigz,
    Bzip2,
    Pbzip2,
    Xz,
    Zstd,
    Lz4,
    Zip,
    Unzip,
    Rar,
    Unrar,
    Unar,
}

impl Engine {
    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "sevenZip" => Self::SevenZip,
            "tar" => Self::Tar,
            "bsdTar" => Self::BsdTar,
            "gzip" => Self::Gzip,
            "pigz" => Self::Pigz,
            "bzip2" => Self::Bzip2,
            "pbzip2" => Self::Pbzip2,
            "xz" => Self::Xz,
            "zstd" => Self::Zstd,
            "lz4" => Self::Lz4,
            "zip" => Self::Zip,
            "unzip" => Self::Unzip,
            "rar" => Self::Rar,
            "unrar" => Self::Unrar,
            "unar" => Self::Unar,
            _ => return None,
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::SevenZip => "sevenZip",
            Self::Tar => "tar",
            Self::BsdTar => "bsdTar",
            Self::Gzip => "gzip",
            Self::Pigz => "pigz",
            Self::Bzip2 => "bzip2",
            Self::Pbzip2 => "pbzip2",
            Self::Xz => "xz",
            Self::Zstd => "zstd",
            Self::Lz4 => "lz4",
            Self::Zip => "zip",
            Self::Unzip => "unzip",
            Self::Rar => "rar",
            Self::Unrar => "unrar",
            Self::Unar => "unar",
        }
    }

    pub fn formats(self) -> &'static [&'static str] {
        match self {
            Self::SevenZip => &["7z", "zip"],
            Self::Tar | Self::BsdTar => &["tar", "tar.gz", "tar.bz2", "tar.xz", "tar.zst"],
            Self::Gzip | Self::Pigz => &["tar.gz", "gz"],
            Self::Bzip2 | Self::Pbzip2 => &["tar.bz2", "bz2"],
            Self::Xz => &["tar.xz", "xz"],
            Self::Zstd => &["tar.zst", "zst"],
            Self::Lz4 => &["tar.lz4", "lz4"],
            Self::Zip => &["zip"],
            Self::Rar => &["rar"],
            _ => &[],
        }
    }

    pub fn extracts(self) -> bool {
        self != Self::Zip
    }

    pub fn is_stream(self) -> bool {
        matches!(
            self,
            Self::Gzip | Self::Pigz | Self::Bzip2 | Self::Pbzip2 | Self::Xz | Self::Zstd | Self::Lz4
        )
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Tool {
    pub name: String,
    pub path: PathBuf,
    pub engine: Engine,
}

pub fn start_configured_zip(runner: &crate::Runner, request: crate::OpRequest, options: Options) -> u64 {
    use crate::journal::{StepKind, StepRecord};
    use crate::runner::Journaling;
    let record = StepRecord::for_paths(StepKind::Compress, &request.sources, Vec::new());
    let journal =
        Journaling::Record { kind: StepKind::Compress, items: record.items, first_name: record.first_name };
    let job = request.clone();
    runner.start_job(
        request,
        journal,
        Box::new(move |ctx| {
            if job.kind != crate::OpKind::Compress || options.validate(None).is_err() {
                ctx.record_error(std::path::Path::new(""), "Unsupported built-in ZIP options".into());
                return Err(crate::Abort::Stopped);
            }
            crate::compress::run_with_level(ctx, &job, options.level)
        }),
    )
}
