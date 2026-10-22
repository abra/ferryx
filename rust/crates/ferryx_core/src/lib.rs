//! Pure logic shared by the file system layer, the operations and the
//! bridge: no I/O here.
//!
//! - [`entry`]: what a panel row is made of.
//! - [`collation`] and [`sorting`]: the orders a panel can show.
//! - [`mask`]: file masks (`*.txt;*.md`) and regular expressions.
//! - [`quick_search`]: typing a few letters to find a row.
//! - [`batch_rename`]: the placeholder language of the Batch Rename dialog.

pub mod batch_rename;
pub mod collation;
pub mod entry;
pub mod mask;
pub mod quick_search;
pub mod sorting;
