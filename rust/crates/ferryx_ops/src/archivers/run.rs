use std::ffi::OsString;
use std::fs;
use std::path::{Component, Path, PathBuf};

use crate::journal::{StepKind, StepRecord};
use crate::runner::Journaling;
use crate::{copy, Abort, ConflictPolicy, OpContext, OpKind, OpOptions, OpRequest, Runner};
use ferryx_vfs::archive;

use super::{catalog, command, process, streams, Engine, Options, Tool};

/// External programs write only to private staging; the core publishes their
/// results, asks about conflicts and records exactly those changes for Undo.
pub fn start(runner: &Runner, request: OpRequest, tool: Tool, format: String) -> u64 {
    start_with_options(runner, request, tool, format, Options::default())
}

pub fn start_with_options(
    runner: &Runner,
    request: OpRequest,
    tool: Tool,
    format: String,
    options: Options,
) -> u64 {
    let kind = if request.kind == OpKind::Compress { StepKind::Compress } else { StepKind::Extract };
    let record = StepRecord::for_paths(kind, &request.sources, Vec::new());
    let journaling = Journaling::Record { kind, items: record.items, first_name: record.first_name };
    let job_request = request.clone();
    runner.start_job(
        request,
        journaling,
        Box::new(move |ctx| {
            let result = run(ctx, &job_request, &tool, &format, &options);
            match result {
                Ok(()) => Ok(()),
                Err(process::Failure::Aborted(abort)) => Err(abort),
                Err(process::Failure::Message(message)) => {
                    let current = ctx.snapshot().current;
                    let path = if current.is_empty() { tool.path.clone() } else { PathBuf::from(current) };
                    ctx.record_error(&path, message);
                    Err(Abort::Stopped)
                }
            }
        }),
    )
}

fn message(value: impl ToString) -> process::Failure {
    process::Failure::Message(value.to_string())
}

fn run(
    ctx: &OpContext,
    request: &OpRequest,
    tool: &Tool,
    format: &str,
    options: &Options,
) -> Result<(), process::Failure> {
    ctx.check().map_err(process::Failure::Aborted)?;
    options.validate(Some(tool.engine)).map_err(message)?;
    if !matches!(request.kind, OpKind::Compress | OpKind::Extract) || request.archive.is_some() {
        return Err(message("External archive engines require whole local archives"));
    }
    if !tool.path.is_absolute() || !catalog::executable(&tool.path) {
        return Err(message("Archiver executable is unavailable"));
    }
    if request.sources.is_empty() || request.sources.iter().any(|s| !s.is_absolute()) {
        return Err(message("Archivers require absolute local source paths"));
    }
    let destination = request.destination.as_deref().ok_or_else(|| message("No destination"))?;
    if !destination.is_absolute() {
        return Err(message("Archive destination must be absolute"));
    }
    let password = request.options.password.as_deref().filter(|p| !p.is_empty());
    if password.is_some_and(|p| p.len() > 1024) {
        return Err(message("Archive password is too long for the external adapter"));
    }
    if password.is_some_and(|p| p.contains(['\r', '\n', '\0'])) {
        return Err(message("Archive password contains a line break"));
    }
    if password.is_some() && tool.engine != Engine::SevenZip {
        return Err(message("Use the built-in engine or 7-Zip for password-protected archives"));
    }
    fs::create_dir_all(destination).map_err(message)?;
    let mut temporary = tempfile::Builder::new();
    temporary.prefix(".ferryx-archive-");
    let stage = if request.kind == OpKind::Compress {
        temporary.tempdir()
    } else {
        temporary.tempdir_in(destination)
    }
    .map_err(message)?;
    if request.kind == OpKind::Compress
        && request.sources.iter().any(|source| source.is_dir() && stage.path().starts_with(source))
    {
        return Err(message("Cannot create an archive containing its own temporary output"));
    }
    match request.kind {
        OpKind::Compress => compress(ctx, request, tool, format, stage.path(), destination, options),
        OpKind::Extract if request.archive.is_none() && tool.engine.extracts() => {
            extract(ctx, request, tool, password, stage.path(), destination, options)
        }
        _ => Err(message("This archive operation is not supported by the selected engine")),
    }
}

fn compress(
    ctx: &OpContext,
    request: &OpRequest,
    tool: &Tool,
    format: &str,
    stage: &Path,
    destination: &Path,
    options: &Options,
) -> Result<(), process::Failure> {
    let password = request.options.password.as_deref().filter(|p| !p.is_empty());
    if !tool.engine.formats().contains(&format) {
        return Err(message("This archiver cannot create the selected format"));
    }
    let name = request.new_name.as_deref().unwrap_or("Archive");
    if name.is_empty()
        || Path::new(name).components().count() != 1
        || !matches!(Path::new(name).components().next(), Some(Component::Normal(_)))
        || name.contains(['/', '\\', '\0'])
    {
        return Err(message("The archive name must be a file name, without a folder"));
    }
    let name = if name.to_lowercase().ends_with(&format!(".{format}")) {
        name.to_string()
    } else {
        format!("{name}.{format}")
    };
    let output = stage.join(&name);
    let mut base = request.sources[0].parent().unwrap_or(Path::new("/")).to_path_buf();
    while request.sources.iter().any(|s| !s.starts_with(&base)) {
        if !base.pop() {
            return Err(message("Sources must share a filesystem root"));
        }
    }
    let sources: Vec<OsString> = request
        .sources
        .iter()
        .map(|source| {
            let relative = source.strip_prefix(&base).expect("common source root");
            Path::new(".").join(relative).into_os_string()
        })
        .collect();
    ctx.set_current(&destination.join(&name));
    ctx.set_totals(0, 0);
    if tool.engine.is_stream() {
        streams::compress(ctx, tool, format, &request.sources, &base, &output, options)?;
    } else {
        let mut command = command::create(tool, format, &output, &sources, password.is_some(), options);
        command.current_dir(&base);
        process::execute(ctx, command, password)?;
    }
    if !output.is_file() {
        return Err(message("Archiver did not create the requested archive"));
    }
    publish(
        ctx,
        vec![output],
        destination,
        Some(name),
        ConflictPolicy::KeepBoth,
        request.options.preserve_attributes,
    )?;
    Ok(())
}

fn extract(
    ctx: &OpContext,
    request: &OpRequest,
    tool: &Tool,
    password: Option<&str>,
    stage: &Path,
    destination: &Path,
    options: &Options,
) -> Result<(), process::Failure> {
    for (index, archive) in request.sources.iter().enumerate() {
        ctx.check().map_err(process::Failure::Aborted)?;
        ctx.set_current(archive);
        ctx.set_totals(0, 0);
        let unpacked = stage.join(index.to_string());
        fs::create_dir(&unpacked).map_err(message)?;
        if tool.engine.is_stream() {
            streams::extract(ctx, tool, archive, &unpacked, options)?;
        } else {
            let mut command = command::extract(tool, archive, options);
            command.current_dir(&unpacked);
            process::execute(ctx, command, password)?;
        }
        let mut files: Vec<PathBuf> = fs::read_dir(&unpacked)
            .map_err(message)?
            .map(|entry| entry.map(|e| e.path()))
            .collect::<Result<_, _>>()
            .map_err(message)?;
        files.sort();
        if request.options.into_folders {
            publish(
                ctx,
                vec![unpacked],
                destination,
                Some(archive::archive_stem(archive)),
                request.options.conflicts,
                request.options.preserve_attributes,
            )?;
        } else if !files.is_empty() {
            publish(
                ctx,
                files,
                destination,
                None,
                request.options.conflicts,
                request.options.preserve_attributes,
            )?;
        }
    }
    Ok(())
}

fn publish(
    ctx: &OpContext,
    sources: Vec<PathBuf>,
    destination: &Path,
    new_name: Option<String>,
    conflicts: ConflictPolicy,
    preserve_attributes: bool,
) -> Result<(), process::Failure> {
    copy::run(
        ctx,
        &OpRequest {
            kind: OpKind::Copy,
            sources,
            archive: None,
            destination: Some(destination.into()),
            new_name,
            options: OpOptions { conflicts, preserve_attributes, ..Default::default() },
        },
    )
    .map_err(process::Failure::Aborted)
}
