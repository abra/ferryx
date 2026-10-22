//! Find Duplicates on a thread; groups arrive as `DuplicatesProgress`
//! events.

use std::cell::RefCell;
use std::path::PathBuf;

use ferryx_ops::duplicates::{self, DuplicateGroup, DuplicatesRequest, Phase};

use crate::api::types::{AppEvent, AppEventKind};
use crate::app;
use crate::tasks::{self, Pacer};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DuplicatesRequestView {
    pub roots: Vec<String>,
    pub min_size: i64,
    /// A mask (`*.jpg;*.png`); empty for every name.
    pub name_mask: String,
    pub include_hidden: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DuplicatesPhaseView {
    Scanning,
    Comparing,
    Hashing,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DuplicateFileView {
    pub path: String,
    pub modified_ms: Option<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DuplicateGroupView {
    pub size: i64,
    pub files: Vec<DuplicateFileView>,
}

/// What a running search says: its phase and counts, the groups settled
/// since the last event, whether it ended.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DuplicatesUpdateView {
    pub task_id: i64,
    pub phase: Option<DuplicatesPhaseView>,
    pub files_scanned: i64,
    pub candidates: i64,
    pub files_hashed: i64,
    pub bytes_done: i64,
    pub current: Option<String>,
    pub groups: Vec<DuplicateGroupView>,
    pub done: bool,
    pub error: Option<String>,
}

impl DuplicatesUpdateView {
    fn empty(task_id: i64) -> DuplicatesUpdateView {
        DuplicatesUpdateView {
            task_id,
            phase: None,
            files_scanned: 0,
            candidates: 0,
            files_hashed: 0,
            bytes_done: 0,
            current: None,
            groups: Vec::new(),
            done: false,
            error: None,
        }
    }
}

fn emit(update: DuplicatesUpdateView) {
    app::emit(AppEvent { duplicates: Some(update), ..AppEvent::of(AppEventKind::DuplicatesProgress, None) });
}

fn group_view(group: DuplicateGroup) -> DuplicateGroupView {
    DuplicateGroupView {
        size: group.size as i64,
        files: group
            .files
            .into_iter()
            .map(|f| DuplicateFileView {
                path: f.path.to_string_lossy().into_owned(),
                modified_ms: f.modified_ms,
            })
            .collect(),
    }
}

/// Starts the search and answers its id.
pub fn start_duplicates(request: DuplicatesRequestView) -> i64 {
    let (id, cancel) = tasks::begin();
    let ops_request = DuplicatesRequest {
        roots: request.roots.iter().map(PathBuf::from).collect(),
        min_size: request.min_size.max(0) as u64,
        name_mask: request.name_mask,
        include_hidden: request.include_hidden,
    };
    let spawned = std::thread::Builder::new().name(format!("duplicates {id}")).spawn(move || {
        let pending = RefCell::new(DuplicatesUpdateView::empty(id));
        let pacer = RefCell::new(Pacer::new());
        let flush = |force: bool| {
            let mut update = pending.borrow_mut();
            let mut pacer = pacer.borrow_mut();
            if force || pacer.due(update.groups.len()) {
                let groups = std::mem::take(&mut update.groups);
                emit(DuplicatesUpdateView { groups, ..update.clone() });
                pacer.sent();
            }
        };
        let result = duplicates::run(
            &ops_request,
            &cancel,
            tasks::BATCH,
            &mut |group| {
                pending.borrow_mut().groups.push(group_view(group));
                flush(false);
            },
            &mut |progress| {
                {
                    let mut update = pending.borrow_mut();
                    update.phase = progress.phase.map(|p| match p {
                        Phase::Scanning => DuplicatesPhaseView::Scanning,
                        Phase::Comparing => DuplicatesPhaseView::Comparing,
                        Phase::Hashing => DuplicatesPhaseView::Hashing,
                    });
                    update.files_scanned = progress.files_scanned as i64;
                    update.candidates = progress.candidates as i64;
                    update.files_hashed = progress.files_hashed as i64;
                    update.bytes_done = progress.bytes_done as i64;
                    update.current = progress.current.clone();
                }
                flush(false);
            },
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
        emit(DuplicatesUpdateView {
            done: true,
            error: Some("could not start the search".to_string()),
            ..DuplicatesUpdateView::empty(id)
        });
    }
    id
}

pub fn cancel_duplicates(task_id: i64) {
    tasks::cancel(task_id);
}
