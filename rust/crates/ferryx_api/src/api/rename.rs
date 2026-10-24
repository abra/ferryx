//! Batch rename: a preview of the new names, then their application.

use std::fs;
use std::path::{Path, PathBuf};

use ferryx_core::batch_rename::{self, RenameItem, RenameProblem};
use ferryx_vfs::native;

use crate::api::types::{
    ApiResult, FerryxError, RenameFailureView, RenameItemView, RenameOptionsView, RenameOutcomeView,
    RenamePairView, RenameProblemView,
};

/// The new name of each item under `options`, with any problem. An
/// invalid search expression fails the whole preview.
pub fn batch_rename_preview(
    items: Vec<RenameItemView>,
    options: RenameOptionsView,
) -> ApiResult<Vec<RenameOutcomeView>> {
    // The preview runs on every keystroke: times are read only when the
    // pattern shows them.
    let dated = batch_rename::uses_dates(&options.pattern);
    let core_items: Vec<RenameItem> = items
        .iter()
        .map(|item| {
            let path = Path::new(&item.path);
            let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            let parent = path
                .parent()
                .and_then(Path::file_name)
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            let grandparent = path
                .parent()
                .and_then(Path::parent)
                .and_then(Path::file_name)
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            let modified_ms = if dated {
                fs::symlink_metadata(path)
                    .ok()
                    .and_then(|m| m.modified().ok())
                    .and_then(native::system_time_ms)
            } else {
                None
            };
            RenameItem { name, parent, grandparent, modified_ms }
        })
        .collect();
    let outcomes =
        batch_rename::plan(&core_items, &options.to_core()).map_err(FerryxError::invalid_pattern)?;
    Ok(items
        .iter()
        .zip(core_items)
        .zip(outcomes)
        .map(|((item, core), outcome)| RenameOutcomeView {
            path: item.path.clone(),
            old_name: core.name,
            new_name: outcome.new_name,
            problem: match outcome.problem {
                None => RenameProblemView::None,
                Some(RenameProblem::Empty) => RenameProblemView::Empty,
                Some(RenameProblem::Invalid) => RenameProblemView::Invalid,
                Some(RenameProblem::Duplicate) => RenameProblemView::Duplicate,
            },
        })
        .collect())
}

/// Renames every pair; answers what failed. What was renamed is one step
/// of the journal.
pub fn batch_rename_apply(pairs: Vec<RenamePairView>) -> Vec<RenameFailureView> {
    let pairs: Vec<(PathBuf, String)> =
        pairs.into_iter().map(|p| (PathBuf::from(p.path), p.new_name)).collect();
    let (failures, done) = ferryx_ops::rename::apply_recorded(&pairs);
    let renamed: Vec<PathBuf> = done.iter().map(|(from, _)| from.clone()).collect();
    crate::tasks::record(
        ferryx_ops::journal::StepKind::Rename,
        &renamed,
        done.into_iter().map(|(from, to)| ferryx_ops::journal::Change::Moved { from, to }).collect(),
    );
    failures
        .into_iter()
        .map(|f| RenameFailureView { path: f.path.to_string_lossy().into_owned(), message: f.message })
        .collect()
}
