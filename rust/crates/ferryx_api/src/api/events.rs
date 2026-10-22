//! Change notifications from Rust to Dart.

use flutter_rust_bridge::frb;

use crate::api::types::AppEvent;
use crate::app;
use crate::frb_generated::StreamSink;

/// Registers `sink` as the receiver of [`AppEvent`]s. Call once at
/// startup; a later call replaces the previous listener.
pub fn subscribe_events(sink: StreamSink<AppEvent>) {
    app::set_event_sink(sink);
}

/// Keeps the events every call sends from now on, for
/// [`take_recorded_events`]: the flows under `tests/` check what each call
/// announces. Not part of the bridge.
#[frb(ignore)]
pub fn record_events() {
    app::record_events();
}

/// The events sent since [`record_events`] or the last call.
#[frb(ignore)]
pub fn take_recorded_events() -> Vec<AppEvent> {
    app::take_events()
}

/// Drops every listing, archive index, search and listener: each test
/// starts clean. Not part of the bridge.
#[frb(ignore)]
pub fn reset_for_tests() {
    app::reset_for_tests();
}
