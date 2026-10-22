//! Folder sizes, for the panel's size column.

use std::path::Path;

use walkdir::WalkDir;

use crate::runner::OpContext;
use crate::types::*;

pub fn run(ctx: &OpContext, request: &OpRequest) -> Result<(), Abort> {
    ctx.set_totals(0, request.sources.len() as u64);
    for source in &request.sources {
        ctx.check()?;
        ctx.set_current(source);
        let bytes = folder_size(ctx, source)?;
        ctx.update(|p| {
            p.sizes.push(FolderSize { path: source.clone(), bytes });
            p.items_done += 1;
        });
    }
    Ok(())
}

/// Bytes of every file under `dir`, links not followed.
pub fn folder_size(ctx: &OpContext, dir: &Path) -> Result<u64, Abort> {
    let mut bytes = 0u64;
    let mut n = 0u32;
    for entry in WalkDir::new(dir).follow_links(false).into_iter().filter_map(Result::ok) {
        n = n.wrapping_add(1);
        if n % 512 == 0 {
            ctx.check()?;
        }
        if entry.file_type().is_file() {
            bytes += entry.metadata().map(|m| m.len()).unwrap_or(0);
        }
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn sums_files_under_folders() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("a/b")).unwrap();
        fs::write(dir.path().join("a/x"), b"123").unwrap();
        fs::write(dir.path().join("a/b/y"), b"4567").unwrap();
        let req = OpRequest {
            kind: OpKind::CalcSizes,
            sources: vec![dir.path().join("a")],
            archive: None,
            destination: None,
            new_name: None,
            options: OpOptions::default(),
        };
        let ctx = OpContext::detached(&req);
        run(&ctx, &req).unwrap();
        let p = ctx.snapshot();
        assert_eq!(p.sizes, vec![FolderSize { path: dir.path().join("a"), bytes: 7 }]);
    }
}
