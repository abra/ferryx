//! Undo and redo of file operations: what the next undo or redo would do,
//! a look at it before, and the walk as an operation.

use ferryx_ops::journal::{Direction, JournalSummary, StepKind, StepSummary};
use ferryx_ops::undo::{self, IssueKind};
use flutter_rust_bridge::frb;

use crate::api::types::{ApiResult, FerryxError, FerryxErrorKind};
use crate::app;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StepKindView {
    Copy,
    Move,
    Trash,
    Rename,
    CreateFolder,
    CreateFile,
    CreateLink,
    Duplicate,
    Compress,
    Extract,
    Synchronize,
}

/// One step of the journal, as the interface names it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StepSummaryView {
    pub id: i64,
    pub kind: StepKindView,
    /// How many items the user acted on.
    pub items: i64,
    /// The first of them, by name.
    pub first_name: String,
    /// Some items were overwritten: their earlier contents are gone.
    pub partial: bool,
    pub at_ms: i64,
}

/// What undo and redo would do next.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct JournalSummaryView {
    pub undo: Option<StepSummaryView>,
    pub redo: Option<StepSummaryView>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UndoIssueKindView {
    /// The item is gone.
    Missing,
    /// The place it goes back to is taken.
    Occupied,
    /// It changed since (a warning).
    Changed,
    /// It was overwritten: its earlier contents are gone (a warning).
    Lost,
    /// It is no longer in the trash.
    NotInTrash,
    /// Items cannot be put back from the trash here.
    Unsupported,
    /// The step changed more items than the journal keeps.
    Truncated,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UndoIssueView {
    pub kind: UndoIssueKindView,
    pub path: String,
    /// Whether the change is left out (else a warning).
    pub blocks: bool,
}

/// A look at the step undo (or redo) would take.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UndoCheckView {
    pub step: StepSummaryView,
    /// The first issues (at most [`MAX_ISSUES`]).
    pub issues: Vec<UndoIssueView>,
    pub issues_total: i64,
    /// Changes that can be walked back, of all that do something.
    pub doable: i64,
    pub total: i64,
}

/// Issues sent at most; the rest are counted.
const MAX_ISSUES: usize = 200;

impl StepKindView {
    #[frb(ignore)]
    pub fn from_ops(kind: StepKind) -> StepKindView {
        match kind {
            StepKind::Copy => StepKindView::Copy,
            StepKind::Move => StepKindView::Move,
            StepKind::Trash => StepKindView::Trash,
            StepKind::Rename => StepKindView::Rename,
            StepKind::CreateFolder => StepKindView::CreateFolder,
            StepKind::CreateFile => StepKindView::CreateFile,
            StepKind::CreateLink => StepKindView::CreateLink,
            StepKind::Duplicate => StepKindView::Duplicate,
            StepKind::Compress => StepKindView::Compress,
            StepKind::Extract => StepKindView::Extract,
            StepKind::Synchronize => StepKindView::Synchronize,
        }
    }
}

impl StepSummaryView {
    #[frb(ignore)]
    pub fn from_ops(step: StepSummary) -> StepSummaryView {
        StepSummaryView {
            id: step.id as i64,
            kind: StepKindView::from_ops(step.kind),
            items: step.items as i64,
            first_name: step.first_name,
            partial: step.partial,
            at_ms: step.at_ms,
        }
    }
}

impl JournalSummaryView {
    #[frb(ignore)]
    pub fn from_ops(summary: JournalSummary) -> JournalSummaryView {
        JournalSummaryView {
            undo: summary.undo.map(StepSummaryView::from_ops),
            redo: summary.redo.map(StepSummaryView::from_ops),
        }
    }
}

fn issue_kind(kind: IssueKind) -> UndoIssueKindView {
    match kind {
        IssueKind::Missing => UndoIssueKindView::Missing,
        IssueKind::Occupied => UndoIssueKindView::Occupied,
        IssueKind::Changed => UndoIssueKindView::Changed,
        IssueKind::Lost => UndoIssueKindView::Lost,
        IssueKind::NotInTrash => UndoIssueKindView::NotInTrash,
        IssueKind::Unsupported => UndoIssueKindView::Unsupported,
        IssueKind::Truncated => UndoIssueKindView::Truncated,
    }
}

fn direction(redo: bool) -> Direction {
    if redo {
        Direction::Redo
    } else {
        Direction::Undo
    }
}

/// What undo and redo would do next. A `JournalChanged` event brings each
/// change of it.
pub fn journal_summary() -> JournalSummaryView {
    JournalSummaryView::from_ops(app::runner().journal().summary())
}

/// A look at the step undo (`redo` false) or redo would take: what cannot
/// be done as it was, by path. `None` when there is nothing to do.
pub fn check_journal_step(redo: bool) -> Option<UndoCheckView> {
    let step = app::runner().journal().peek(direction(redo))?;
    let check = undo::check(&step);
    Some(UndoCheckView {
        step: StepSummaryView::from_ops(step.summary()),
        issues_total: check.issues.len() as i64,
        issues: check
            .issues
            .into_iter()
            .take(MAX_ISSUES)
            .map(|issue| UndoIssueView {
                kind: issue_kind(issue.kind),
                blocks: issue.kind.blocks(),
                path: issue.path.to_string_lossy().into_owned(),
            })
            .collect(),
        doable: check.doable as i64,
        total: check.total as i64,
    })
}

/// Undoes (`redo` false) or redoes the step `step_id` as an operation and
/// answers its id; fails when that step is no longer the next one.
pub fn walk_journal_step(redo: bool, step_id: i64) -> ApiResult<i64> {
    undo::start(app::runner(), direction(redo), step_id as u64)
        .map(|id| id as i64)
        .ok_or_else(|| FerryxError::new(FerryxErrorKind::NotFound, "the step is no longer the next one"))
}

/// Drops the step `step_id` (one that cannot be done any more) from the
/// top of its stack, so the one before it comes next.
pub fn forget_journal_step(redo: bool, step_id: i64) -> bool {
    app::runner().journal().forget(direction(redo), step_id as u64)
}
