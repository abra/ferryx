//! flutter_rust_bridge surface of Ferryx.
//!
//! The Flutter app talks only to the functions under [`api`]. They work on
//! the process-wide state in [`app`] (open listings and their watchers, the
//! operations runner, running searches) and push what changes to Dart
//! through one event stream ([`api::events`]).

pub mod api;
mod app;
mod frb_generated;
