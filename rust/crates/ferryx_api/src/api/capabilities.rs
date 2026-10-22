//! What this desktop can do that others cannot: the interface hides the
//! commands that would not work.

use std::path::Path;

/// Where macOS keeps the Spotlight command line.
const MDFIND: &str = "/usr/bin/mdfind";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CapabilitiesView {
    /// Finder tags can be read and written (macOS).
    pub finder_tags: bool,
    /// Find Files can ask the Spotlight index (macOS, with `mdfind`).
    pub spotlight: bool,
}

#[flutter_rust_bridge::frb(sync)]
pub fn capabilities() -> CapabilitiesView {
    CapabilitiesView {
        finder_tags: ferryx_vfs::tags::supported(),
        spotlight: cfg!(target_os = "macos") && Path::new(MDFIND).exists(),
    }
}
