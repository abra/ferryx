//! Compare and synchronize folders: the comparison of two trees on a
//! thread (rows arrive as `CompareProgress` events), the synchronization
//! and the panels' content comparison as operations.

use std::cell::RefCell;
use std::path::PathBuf;

use ferryx_ops::runner::{Job, Journaling};
use ferryx_ops::sync::{
    self as ops_sync, CompareRequest, CompareRow, ContentPair, RowState, SideInfo, SyncAction, SyncItem,
    SyncPlan,
};
use ferryx_ops::{OpKind, OpOptions, OpRequest};
use flutter_rust_bridge::frb;

use crate::api::types::{AppEvent, AppEventKind};
use crate::app;
use crate::tasks::{self, Pacer};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FolderCompareRequestView {
    pub left: String,
    pub right: String,
    pub recursive: bool,
    pub compare_content: bool,
    /// Times this close count as the same.
    pub time_tolerance_ms: i64,
    /// A mask for files (`*.jpg;*.png`); empty for all.
    pub name_mask: String,
    pub include_hidden: bool,
    pub case_sensitive: bool,
}

/// One side of a compared item.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SideInfoView {
    pub size: i64,
    pub modified_ms: Option<i64>,
    pub is_dir: bool,
    pub is_symlink: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CompareStateView {
    LeftOnly,
    RightOnly,
    LeftNewer,
    RightNewer,
    Equal,
    Different,
    Conflict,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompareRowView {
    /// The path under the left folder, with `/`.
    pub left_rel: String,
    /// The path under the right folder when it is spelled otherwise
    /// (names matched ignoring case).
    pub right_rel: Option<String>,
    pub is_dir: bool,
    pub left: Option<SideInfoView>,
    pub right: Option<SideInfoView>,
    pub state: CompareStateView,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompareErrorView {
    pub path: String,
    pub message: String,
}

/// What a running comparison says: rows so far, where it is, whether it
/// ended.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompareUpdateView {
    pub task_id: i64,
    pub rows: Vec<CompareRowView>,
    pub folders: i64,
    pub files: i64,
    pub bytes_compared: i64,
    pub current: Option<String>,
    pub errors: Vec<CompareErrorView>,
    pub done: bool,
    /// Why it could not run (a missing folder, a bad mask).
    pub error: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SyncActionView {
    CopyToRight,
    CopyToLeft,
    DeleteLeft,
    DeleteRight,
}

/// One item to synchronize, with both sides as the comparison saw them.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SyncItemView {
    pub left_rel: String,
    pub right_rel: Option<String>,
    pub is_dir: bool,
    pub action: SyncActionView,
    pub left: Option<SideInfoView>,
    pub right: Option<SideInfoView>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SyncPlanView {
    pub left: String,
    pub right: String,
    pub recursive: bool,
    pub items: Vec<SyncItemView>,
    pub preserve_attributes: bool,
    pub verify: bool,
}

/// Two files to compare byte for byte.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ContentPairView {
    pub left: String,
    pub right: String,
}

impl SideInfoView {
    fn from_ops(side: SideInfo) -> SideInfoView {
        SideInfoView {
            size: side.size as i64,
            modified_ms: side.modified_ms,
            is_dir: side.is_dir,
            is_symlink: side.is_symlink,
        }
    }

    fn to_ops(self) -> SideInfo {
        SideInfo {
            size: self.size.max(0) as u64,
            modified_ms: self.modified_ms,
            is_dir: self.is_dir,
            is_symlink: self.is_symlink,
        }
    }
}

impl CompareRowView {
    #[frb(ignore)]
    pub fn from_ops(row: CompareRow) -> CompareRowView {
        CompareRowView {
            right_rel: (row.right_rel != row.left_rel).then_some(row.right_rel),
            left_rel: row.left_rel,
            is_dir: row.is_dir,
            left: row.left.map(SideInfoView::from_ops),
            right: row.right.map(SideInfoView::from_ops),
            state: match row.state {
                RowState::LeftOnly => CompareStateView::LeftOnly,
                RowState::RightOnly => CompareStateView::RightOnly,
                RowState::LeftNewer => CompareStateView::LeftNewer,
                RowState::RightNewer => CompareStateView::RightNewer,
                RowState::Equal => CompareStateView::Equal,
                RowState::Different => CompareStateView::Different,
                RowState::Conflict => CompareStateView::Conflict,
            },
        }
    }
}

impl CompareUpdateView {
    fn empty(task_id: i64) -> CompareUpdateView {
        CompareUpdateView {
            task_id,
            rows: Vec::new(),
            folders: 0,
            files: 0,
            bytes_compared: 0,
            current: None,
            errors: Vec::new(),
            done: false,
            error: None,
        }
    }
}

fn emit(update: CompareUpdateView) {
    app::emit(AppEvent { compare: Some(update), ..AppEvent::of(AppEventKind::CompareProgress, None) });
}

/// Starts comparing two folders and answers the task's id; rows come in
/// `CompareProgress` events, the last one `done`.
pub fn start_folder_compare(request: FolderCompareRequestView) -> i64 {
    let (id, cancel) = tasks::begin();
    let ops_request = CompareRequest {
        left: PathBuf::from(&request.left),
        right: PathBuf::from(&request.right),
        recursive: request.recursive,
        compare_content: request.compare_content,
        time_tolerance_ms: request.time_tolerance_ms.max(0) as u64,
        name_mask: request.name_mask,
        include_hidden: request.include_hidden,
        case_sensitive: request.case_sensitive,
    };
    let spawned = std::thread::Builder::new().name(format!("compare {id}")).spawn(move || {
        let pending = RefCell::new(CompareUpdateView::empty(id));
        let pacer = RefCell::new(Pacer::new());
        let flush = |force: bool| {
            let mut update = pending.borrow_mut();
            let mut pacer = pacer.borrow_mut();
            if force || pacer.due(update.rows.len()) {
                let rows = std::mem::take(&mut update.rows);
                let errors = std::mem::take(&mut update.errors);
                emit(CompareUpdateView { rows, errors, ..update.clone() });
                pacer.sent();
            }
        };
        let result = ops_sync::compare(
            &ops_request,
            &cancel,
            tasks::BATCH,
            &mut |row| {
                pending.borrow_mut().rows.push(CompareRowView::from_ops(row));
                flush(false);
            },
            &mut |progress| {
                {
                    let mut update = pending.borrow_mut();
                    update.folders = progress.folders as i64;
                    update.files = progress.files as i64;
                    update.bytes_compared = progress.bytes_compared as i64;
                    update.current = progress.current.clone();
                }
                flush(false);
            },
            &mut |path, message| pending.borrow_mut().errors.push(CompareErrorView { path, message }),
        );
        {
            let mut update = pending.borrow_mut();
            update.done = true;
            update.current = None;
            update.error = result.err();
        }
        flush(true);
        tasks::end(id);
    });
    if spawned.is_err() {
        emit(CompareUpdateView {
            done: true,
            error: Some("could not start the comparison".to_string()),
            ..CompareUpdateView::empty(id)
        });
    }
    id
}

pub fn cancel_folder_compare(task_id: i64) {
    tasks::cancel(task_id);
}

/// Carries out `plan` as an operation (copies, then deletions to the
/// trash) and answers its id.
pub fn start_synchronize(plan: SyncPlanView) -> i64 {
    let ops_plan = SyncPlan {
        left: PathBuf::from(&plan.left),
        right: PathBuf::from(&plan.right),
        recursive: plan.recursive,
        preserve_attributes: plan.preserve_attributes,
        verify: plan.verify,
        items: plan
            .items
            .into_iter()
            .map(|item| SyncItem {
                right_rel: item.right_rel.unwrap_or_else(|| item.left_rel.clone()),
                left_rel: item.left_rel,
                is_dir: item.is_dir,
                action: match item.action {
                    SyncActionView::CopyToRight => SyncAction::CopyToRight,
                    SyncActionView::CopyToLeft => SyncAction::CopyToLeft,
                    SyncActionView::DeleteLeft => SyncAction::DeleteLeft,
                    SyncActionView::DeleteRight => SyncAction::DeleteRight,
                },
                left: item.left.map(SideInfoView::to_ops),
                right: item.right.map(SideInfoView::to_ops),
            })
            .collect(),
    };
    let request = OpRequest {
        kind: OpKind::Synchronize,
        sources: vec![ops_plan.left.clone()],
        archive: None,
        destination: Some(ops_plan.right.clone()),
        new_name: None,
        options: OpOptions::default(),
    };
    let journaling = Journaling::Record {
        kind: ferryx_ops::journal::StepKind::Synchronize,
        items: ops_plan.items.len() as u64,
        first_name: ferryx_ops::journal::display_name(&ops_plan.left),
    };
    let job: Job = Box::new(move |ctx| ops_sync::run_sync(ctx, &ops_plan));
    app::runner().start_job(request, journaling, job) as i64
}

/// Compares each pair of files byte for byte as an operation and answers
/// its id; once it finished, [`take_content_differences`] names the pairs
/// that differ.
pub fn start_content_compare(pairs: Vec<ContentPairView>) -> i64 {
    let pairs: Vec<ContentPair> = pairs
        .into_iter()
        .map(|p| ContentPair { left: PathBuf::from(p.left), right: PathBuf::from(p.right) })
        .collect();
    let request = OpRequest {
        kind: OpKind::CompareContents,
        sources: pairs.iter().map(|p| p.left.clone()).collect(),
        archive: None,
        destination: pairs.first().and_then(|p| p.right.parent()).map(PathBuf::from),
        new_name: None,
        options: OpOptions::default(),
    };
    let differing = std::sync::Arc::new(parking_lot::Mutex::new(Vec::new()));
    let found = differing.clone();
    let job: Job = Box::new(move |ctx| ops_sync::compare_pairs(ctx, &pairs, &found));
    let id = app::runner().start_job(request, Journaling::Off, job) as i64;
    // Kept under the id before Dart learns it, so it is there to take.
    tasks::keep_differences(id, differing);
    id
}

/// The indexes of the pairs the content comparison `op_id` found
/// different (or could not read); empty once taken or for another id.
pub fn take_content_differences(op_id: i64) -> Vec<i64> {
    tasks::take_differences(op_id).into_iter().map(|i| i as i64).collect()
}
