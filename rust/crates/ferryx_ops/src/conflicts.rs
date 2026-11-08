//! File conflict decisions shared by native copies and confined archive
//! extraction. The caller performs the chosen write through its own I/O.

use crate::runner::OpContext;
use crate::types::*;

pub(crate) enum FileChoice {
    Replace,
    KeepBoth,
    Skip,
}

pub(crate) fn file_choice(
    ctx: &OpContext,
    source_size: Option<u64>,
    source_modified: Option<i64>,
    existing: ConflictSide,
    policy: ConflictPolicy,
) -> Result<FileChoice, Abort> {
    let existing_modified = existing.modified_ms;
    let answer = match policy {
        ConflictPolicy::Overwrite => Answer::Overwrite,
        ConflictPolicy::OverwriteOlder => Answer::OverwriteOlderAll,
        ConflictPolicy::Skip => Answer::Skip,
        ConflictPolicy::KeepBoth => Answer::KeepBoth,
        ConflictPolicy::Ask => ctx.ask_conflict(
            ConflictSide {
                path: String::new(),
                size: source_size,
                modified_ms: source_modified,
                is_dir: false,
            },
            existing,
            vec![
                Answer::Overwrite,
                Answer::OverwriteAll,
                Answer::OverwriteOlderAll,
                Answer::Skip,
                Answer::SkipAll,
                Answer::KeepBoth,
                Answer::KeepBothAll,
                Answer::Abort,
            ],
        )?,
    };
    Ok(match answer {
        Answer::Overwrite | Answer::OverwriteAll => FileChoice::Replace,
        Answer::OverwriteOlderAll => match (source_modified, existing_modified) {
            (Some(source), Some(existing)) if source > existing => FileChoice::Replace,
            _ => FileChoice::Skip,
        },
        Answer::KeepBoth | Answer::KeepBothAll => FileChoice::KeepBoth,
        Answer::Abort => return Err(Abort::Stopped),
        _ => FileChoice::Skip,
    })
}
