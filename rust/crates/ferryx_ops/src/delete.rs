//! Delete for good, or move to the trash.

use std::fs;
use std::path::Path;

use ferryx_vfs::error::VfsError;
use walkdir::WalkDir;

use crate::identity::FileIdentity;
use crate::journal::Change;
use crate::runner::OpContext;
use crate::types::*;

pub fn run(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    if request.options.source_identities.as_ref().is_some_and(|ids| ids.len() != request.sources.len()) {
        ctx.record_error(Path::new(""), "the deletion request has missing or extra file identities".into());
        return Err(Abort::Stopped);
    }
    match request.kind {
        OpKind::Trash => trash(ctx, request),
        _ => delete(ctx, request),
    }
}

fn expected(request: &OpRequest, index: usize) -> Option<&str> {
    request.options.source_identities.as_ref().map(|ids| ids[index].as_str())
}

fn still_selected(ctx: &OpContext, path: &Path, expected: Option<&str>) -> bool {
    let Some(expected) = expected else { return true };
    let message = match FileIdentity::of(path) {
        Ok(id) if id.token() == expected => return true,
        Ok(_) => format!("{} was replaced after it was selected for deletion", path.display()),
        Err(error) => VfsError::io(&error, path).message,
    };
    ctx.record_error(path, message);
    false
}

/// Items trashed at once: the freedesktop trash is listed once per batch
/// to find the receipts.
const TRASH_BATCH: usize = 64;

/// Moves the sources to the trash, keeping a receipt of each for undo;
/// an item that fails is asked about on its own.
fn trash(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    ctx.set_totals(0, request.sources.len() as u64);
    for (chunk, batch) in request.sources.chunks(TRASH_BATCH).enumerate() {
        ctx.check()?;
        ctx.set_current(&batch[0]);
        let identity = |index| expected(request, chunk * TRASH_BATCH + index);
        let results = ferryx_vfs::trash::trash_items_when(batch, |index, path| {
            still_selected(ctx, path, identity(index))
        });
        for (index, (path, result)) in batch.iter().zip(results).enumerate() {
            let mut result = result;
            while let Some(outcome) = result {
                match outcome {
                    Ok(receipt) => {
                        ctx.record(Change::Trashed { receipt });
                        break;
                    }
                    Err(e) => {
                        if !ctx.ask_error(path, &e)? || !still_selected(ctx, path, identity(index)) {
                            break;
                        }
                        let retried = ferryx_vfs::trash::trash_items(std::slice::from_ref(path));
                        result = retried.into_iter().next();
                    }
                }
            }
            ctx.item_done();
        }
    }
    Ok(())
}

fn delete(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    let mut items = 0u64;
    let mut selected = Vec::new();
    for (index, source) in request.sources.iter().enumerate() {
        ctx.check()?;
        let identity = expected(request, index);
        if !still_selected(ctx, source, identity) {
            continue;
        }
        selected.push((source, identity));
        items += WalkDir::new(source).follow_links(false).into_iter().filter_map(Result::ok).count() as u64;
    }
    ctx.set_totals(0, items);
    for (source, identity) in selected {
        remove(ctx, source, identity.map(|id| (source.as_path(), id)))?;
    }
    Ok(())
}

/// Removes `path`, a folder's contents first. Returns false if the selected root changed.
fn remove(ctx: &OpContext, path: &Path, root: Option<(&Path, &str)>) -> Result<bool, Abort> {
    ctx.check()?;
    ctx.set_current(path);
    let still_selected = || root.is_none_or(|(path, identity)| still_selected(ctx, path, Some(identity)));
    let meta = loop {
        if !still_selected() {
            return Ok(false);
        }
        match fs::symlink_metadata(path) {
            Ok(meta) => break meta,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(true),
            Err(e) => {
                if !ctx.ask_error(path, &VfsError::io(&e, path))? {
                    return Ok(true);
                }
            }
        }
    };
    if meta.is_dir() {
        let children: Vec<_> = match fs::read_dir(path) {
            Ok(read) => read.filter_map(Result::ok).map(|e| e.path()).collect(),
            Err(e) => {
                ctx.ask_error(path, &VfsError::io(&e, path))?;
                return Ok(true);
            }
        };
        for child in children {
            if !remove(ctx, &child, root)? {
                return Ok(false);
            }
        }
    }
    loop {
        if !still_selected() {
            return Ok(false);
        }
        let result = if meta.is_dir() { fs::remove_dir(path) } else { fs::remove_file(path) };
        match result {
            Ok(()) => break,
            Err(e) => {
                let error = VfsError::io(&e, path);
                if !ctx.ask_error(path, &error)? {
                    return Ok(true);
                }
            }
        }
    }
    ctx.item_done();
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn skips_a_replaced_path_for_both_delete_and_trash() {
        for kind in [OpKind::Delete, OpKind::Trash] {
            let dir = tempfile::tempdir().unwrap();
            let source = dir.path().join("item");
            let original = dir.path().join("saved");
            fs::create_dir(&source).unwrap();
            fs::write(source.join("child"), b"original").unwrap();
            let identity = FileIdentity::of(&source).unwrap().token();
            fs::rename(&source, &original).unwrap();
            fs::create_dir(&source).unwrap();
            fs::write(source.join("child"), b"replacement").unwrap();
            let req = OpRequest {
                kind,
                sources: vec![source.clone()],
                archive: None,
                destination: None,
                new_name: None,
                options: OpOptions { source_identities: Some(vec![identity]), ..Default::default() },
            };
            let ctx = OpContext::detached(&req);
            run(&ctx, &req).unwrap();
            assert_eq!(fs::read(source.join("child")).unwrap(), b"replacement");
            assert_eq!(fs::read(original.join("child")).unwrap(), b"original");
            assert_eq!(ctx.snapshot().errors.len(), 1);
            assert!(ctx.recorded().is_empty());
        }
    }

    #[test]
    fn deletes_a_tree() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("r");
        fs::create_dir_all(root.join("a/b")).unwrap();
        fs::write(root.join("a/b/c"), b"c").unwrap();
        fs::write(root.join("d"), b"d").unwrap();
        let req = OpRequest {
            kind: OpKind::Delete,
            sources: vec![root.clone()],
            archive: None,
            destination: None,
            new_name: None,
            options: OpOptions::default(),
        };
        let ctx = OpContext::detached(&req);
        run(&ctx, &req).unwrap();
        assert!(!root.exists());
        assert_eq!(ctx.snapshot().items_done, 5);
    }
}
