//! Everything Flutter can call. Each module maps to one Dart file.

pub mod archives;
pub mod attrs;
pub mod events;
pub mod files;
pub mod find;
pub mod listing;
pub mod ops;
pub mod rename;
pub mod system;
pub mod types;

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
