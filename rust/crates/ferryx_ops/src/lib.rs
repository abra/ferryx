//! Operations on files, each on a thread of its own, reporting progress
//! through one listener and asking questions (a conflict, an error) that
//! the interface answers.
//!
//! [`Runner`] starts, pauses, cancels and answers; the modules do the work
//! through an [`OpContext`] that checks for cancellation, waits while
//! paused and reports.

pub mod compress;
pub mod copy;
pub mod delete;
pub mod extract;
pub mod find;
pub mod rename;
pub mod runner;
pub mod sizes;
pub mod types;

pub use runner::{OpContext, Runner};
pub use types::*;
