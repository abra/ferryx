use std::fs::File;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

use super::{
    command,
    process::{self, Failure, Pipes},
    Options, Tool,
};
use crate::OpContext;

/// Check pause/cancel between TAR chunks without buffering an archive in memory.
struct Checked<'a, T> {
    ctx: &'a OpContext,
    inner: T,
}
impl<T: Read> Read for Checked<'_, T> {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        self.ctx.check().map_err(|_| io::Error::other("Archive operation stopped"))?;
        self.inner.read(buffer)
    }
}
impl<T: Write> Write for Checked<'_, T> {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        self.ctx.check().map_err(|_| io::Error::other("Archive operation stopped"))?;
        self.inner.write(buffer)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.inner.flush()
    }
}

pub fn compress(
    ctx: &OpContext,
    tool: &Tool,
    format: &str,
    sources: &[PathBuf],
    base: &Path,
    output: &Path,
    options: &Options,
) -> Result<(), Failure> {
    let mut pipes =
        Pipes { output: Some(File::create(output).map_err(failed)?.into()), ..Default::default() };
    if format.starts_with("tar.") {
        pipes.feed = Some(Box::new(move |stdin| {
            let mut builder = tar::Builder::new(Checked { ctx, inner: stdin });
            builder.follow_symlinks(false);
            for source in sources {
                ctx.check().map_err(|_| io::Error::other("Archive operation stopped"))?;
                let name = source.strip_prefix(base).map_err(io::Error::other)?;
                if source.symlink_metadata()?.is_dir() {
                    builder.append_dir_all(name, source)?;
                } else {
                    builder.append_path_with_name(source, name)?;
                }
            }
            builder.finish()
        }));
    } else {
        let [source] = sources else {
            return Err(Failure::Message(
                "Stream compression requires one regular file; choose TAR for folders or multiple files"
                    .into(),
            ));
        };
        if !source.symlink_metadata().map_err(failed)?.is_file() {
            return Err(Failure::Message(
                "Stream compression requires one regular file; choose TAR for folders".into(),
            ));
        }
        pipes.input = Some(File::open(source).map_err(failed)?.into());
    }
    process::execute_with_pipes(ctx, command::stream(tool, false, options), None, pipes)
}

pub fn extract(
    ctx: &OpContext,
    tool: &Tool,
    archive: &Path,
    destination: &Path,
    options: &Options,
) -> Result<(), Failure> {
    let mut pipes = Pipes { input: Some(File::open(archive).map_err(failed)?.into()), ..Default::default() };
    let name = archive.file_name().unwrap_or_default().to_string_lossy();
    let lower = name.to_lowercase();
    let tar = lower.contains(".tar.")
        || [".tgz", ".tbz", ".tbz2", ".txz", ".tzst"].iter().any(|suffix| lower.ends_with(suffix));
    if tar {
        pipes.consume = Some(Box::new(move |stdout| {
            let mut input = Checked { ctx, inner: stdout };
            {
                let mut archive = tar::Archive::new(&mut input);
                archive.set_preserve_permissions(false);
                archive.unpack(destination)?;
            }
            // TAR ends before its padding; drain the decoder so it can verify
            // its checksum and exit without a broken pipe.
            io::copy(&mut input, &mut io::sink())?;
            Ok(())
        }));
    } else {
        let name =
            name.rsplit_once('.').map(|(stem, _)| stem).filter(|name| !name.is_empty()).unwrap_or("unpacked");
        pipes.output = Some(File::create(destination.join(name)).map_err(failed)?.into());
    }
    process::execute_with_pipes(ctx, command::stream(tool, true, options), None, pipes)
}

fn failed(error: io::Error) -> Failure {
    Failure::Message(error.to_string())
}
