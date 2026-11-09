import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import 'mapping.dart';
import 'rust/api/events.dart';
import 'rust/api/types.dart' as rust;
import 'rust/frb_generated.dart';

/// Lifecycle of the Rust core inside this process.
///
/// Initialises the bridge once, exposes the event stream and wraps every
/// call so Rust errors reach Dart as [FerryxException].
class FerryxBackend {
  FerryxBackend._(this._events);

  final Stream<rust.AppEvent> _events;
  static Future<FerryxBackend>? _initialization;

  /// Loads the native library and subscribes to its events once per isolate.
  /// Bootstrap retries reuse this bridge and event stream;
  /// repositories and their subscriptions belong to each bootstrap attempt.
  ///
  /// [externalLibrary] lets tests point at a locally built `libferryx_api`.
  static Future<FerryxBackend> initialize({
    ExternalLibrary? externalLibrary,
  }) => _initialization ??= _initialize(externalLibrary);

  static Future<FerryxBackend> _initialize(ExternalLibrary? library) async {
    try {
      await FerryxRustLib.init(externalLibrary: library);
      final events = subscribeEvents().asBroadcastStream();
      return FerryxBackend._(events);
    } on Object {
      // FRB may already own ports when its Rust initializer fails.
      _initialization = null;
      FerryxRustLib.dispose();
      rethrow;
    }
  }

  /// Notifications from the core; a broadcast stream.
  Stream<rust.AppEvent> get events => _events;

  /// Runs [call] and converts a Rust-side failure into [FerryxException].
  static Future<T> guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on rust.FerryxError catch (error) {
      throw FerryxException(
        errorKindFromView(error.kind),
        error.message,
        path: error.path,
      );
    }
  }
}
