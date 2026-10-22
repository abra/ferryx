//! Everything Flutter can call. Each module maps to one Dart file.

pub mod attrs;
pub mod checksum;
pub mod duplicates;
pub mod events;
pub mod files;
pub mod find;
pub mod journal;
pub mod listing;
pub mod ops;
pub mod rename;
pub mod sync;
pub mod system;
pub mod terminal;
pub mod types;
pub mod volume_id;

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
