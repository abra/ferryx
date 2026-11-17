//! File operations in the background; progress arrives as events.

use std::path::Path;

use ferryx_ops::identity::FileIdentity;
use ferryx_vfs::error::VfsError;

use crate::api::types::{AnswerView, ApiResult, OpRequestView, ProgressView};
use crate::app;

/// Identifies local items in order before asking the user to delete them.
pub fn capture_delete_identities(paths: Vec<String>) -> ApiResult<Vec<String>> {
    paths
        .iter()
        .map(|path| {
            let path = Path::new(path);
            FileIdentity::of(path).map(FileIdentity::token).map_err(|e| VfsError::io(&e, path).into())
        })
        .collect()
}

/// Starts the operation and answers its id; every change of its progress
/// comes as an `OperationProgress` event.
pub fn start_operation(request: OpRequestView) -> i64 {
    app::runner().start(request.to_ops()) as i64
}

pub fn pause_operation(id: i64) {
    app::runner().pause(id as u64);
}

pub fn resume_operation(id: i64) {
    app::runner().resume(id as u64);
}

pub fn cancel_operation(id: i64) {
    app::runner().cancel(id as u64);
}

/// Answers the question `question_id` the operation `id` is waiting on.
pub fn answer_operation(id: i64, question_id: i64, answer: AnswerView) {
    app::runner().answer(id as u64, question_id as u64, answer.to_ops());
}

pub fn operation_progress(id: i64) -> Option<ProgressView> {
    app::runner().progress(id as u64).map(ProgressView::from)
}

pub fn list_operations() -> Vec<ProgressView> {
    app::runner().all().into_iter().map(ProgressView::from).collect()
}

/// Forgets a finished operation.
pub fn forget_operation(id: i64) {
    if app::runner().remove(id as u64) {
        crate::tasks::take_differences(id);
    }
}
