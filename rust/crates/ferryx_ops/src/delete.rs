//! Delete for good, or move to the trash.

use std::fs;
use std::path::Path;

use ferryx_vfs::error::VfsError;
use walkdir::WalkDir;

use crate::journal::Change;
use crate::runner::OpContext;
use crate::types::*;

pub fn run(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    match request.kind {
        OpKind::Trash => trash(ctx, request),
        _ => delete(ctx, request),
    }
}

/// Items trashed at once: the freedesktop trash is listed once per batch
/// to find the receipts.
const TRASH_BATCH: usize = 64;

/// Moves the sources to the trash, keeping a receipt of each for undo;
/// an item that fails is asked about on its own.
fn trash(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    ctx.set_totals(0, request.sources.len() as u64);
    for batch in request.sources.chunks(TRASH_BATCH) {
        ctx.check()?;
        ctx.set_current(&batch[0]);
        let results = ferryx_vfs::trash::trash_items(batch);
        for (path, result) in batch.iter().zip(results) {
            let mut result = result;
            loop {
                match result {
                    Ok(receipt) => {
                        ctx.record(Change::Trashed { receipt });
                        break;
                    }
                    Err(e) => {
                        if !ctx.ask_error(path, &e)? {
                            break;
                        }
                        let retried = ferryx_vfs::trash::trash_items(std::slice::from_ref(path));
                        result = retried.into_iter().next().unwrap_or_else(|| Err(e.clone()));
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
    for source in &request.sources {
        ctx.check()?;
        items += WalkDir::new(source).follow_links(false).into_iter().filter_map(Result::ok).count() as u64;
    }
    ctx.set_totals(0, items);
    for source in &request.sources {
        remove(ctx, source)?;
    }
    Ok(())
}

/// Removes `path`, a folder's contents first, asking on each error.
fn remove(ctx: &OpContext, path: &Path) -> Result<(), Abort> {
    ctx.check()?;
    ctx.set_current(path);
    let meta = loop {
        match fs::symlink_metadata(path) {
            Ok(meta) => break meta,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(e) => {
                if !ctx.ask_error(path, &VfsError::io(&e, path))? {
                    return Ok(());
                }
            }
        }
    };
    if meta.is_dir() {
        let children: Vec<_> = match fs::read_dir(path) {
            Ok(read) => read.filter_map(Result::ok).map(|e| e.path()).collect(),
            Err(e) => {
                ctx.ask_error(path, &VfsError::io(&e, path))?;
                return Ok(());
            }
        };
        for child in children {
            remove(ctx, &child)?;
        }
    }
    loop {
        let result = if meta.is_dir() { fs::remove_dir(path) } else { fs::remove_file(path) };
        match result {
            Ok(()) => break,
            Err(e) => {
                let error = VfsError::io(&e, path);
                if !ctx.ask_error(path, &error)? {
                    return Ok(());
                }
            }
        }
    }
    ctx.item_done();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

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
