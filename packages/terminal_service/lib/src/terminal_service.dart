import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;

/// A shell running in the core's pseudo-terminal.
abstract interface class TerminalSession {
  /// Output, state changes and the end, in order; single subscription.
  Stream<TerminalUpdate> get updates;

  /// Types [bytes] into the shell (UTF-8 text, escape sequences). After
  /// the shell ended it is dropped.
  void write(List<int> bytes);

  /// The view's size in character cells.
  void resize(int cols, int rows);

  /// One [TerminalOutput] has been parsed: the core sends the next.
  void ack();

  /// The shell's state now; unknown parts are `null`.
  TerminalShellState state();

  /// Types `cd` to [folder] when the shell waits at its prompt somewhere
  /// else; whether it did.
  Future<bool> changeDirectory(String folder);

  /// Hangs up the shell. Idempotent.
  Future<void> close();
}

/// Starts terminal sessions in the core and closes them with the app.
class TerminalService {
  final _open = <TerminalSession>{};

  /// Starts a shell; throws [FerryxException] when it cannot (a shell path
  /// that does not exist or is not a program).
  Future<TerminalSession> start(TerminalStart start) async {
    final id = await rust.FerryxBackend.guard(
      () => rust.terminalStart(
        options: rust.TerminalStartView(
          shell: start.shell,
          folder: start.folder,
          cols: start.cols.clamp(1, 1000),
          rows: start.rows.clamp(1, 1000),
          locale: start.locale,
        ),
      ),
    );
    late final _CoreSession session;
    session = _CoreSession(id, onClosed: () => _open.remove(session));
    _open.add(session);
    return session;
  }

  /// The shell a session runs when the settings name none.
  String defaultShell() => rust.terminalDefaultShell();

  /// Closes every session still open.
  Future<void> dispose() async {
    for (final session in [..._open]) {
      await session.close();
    }
  }
}

class _CoreSession implements TerminalSession {
  _CoreSession(this._id, {required this.onClosed});

  final int _id;
  final void Function() onClosed;
  bool _closed = false;

  @override
  late final Stream<TerminalUpdate> updates = rust
      .terminalEvents(id: _id)
      .map(_fromEvent);

  static TerminalUpdate _fromEvent(rust.TerminalEvent event) =>
      switch (event.kind) {
        rust.TerminalEventKind.output => TerminalOutput(event.output),
        rust.TerminalEventKind.state => TerminalShellState(
          idle: event.idle,
          folder: event.folder,
        ),
        rust.TerminalEventKind.exited => TerminalExited(event.exitCode),
      };

  @override
  void write(List<int> bytes) {
    if (_closed || bytes.isEmpty) return;
    try {
      rust.terminalWrite(id: _id, data: bytes);
    } on rust.FerryxError {
      // The shell has ended; its exit comes on [updates].
    }
  }

  @override
  void resize(int cols, int rows) {
    if (_closed) return;
    try {
      rust.terminalResize(
        id: _id,
        cols: cols.clamp(1, 1000),
        rows: rows.clamp(1, 1000),
      );
    } on rust.FerryxError {
      // Gone: nothing to size.
    }
  }

  @override
  void ack() {
    if (!_closed) rust.terminalAck(id: _id);
  }

  @override
  TerminalShellState state() {
    if (_closed) return const TerminalShellState();
    try {
      final view = rust.terminalState(id: _id);
      return TerminalShellState(idle: view.idle, folder: view.folder);
    } on rust.FerryxError {
      return const TerminalShellState();
    }
  }

  @override
  Future<bool> changeDirectory(String folder) async {
    if (_closed) return false;
    try {
      return await rust.terminalChangeDirectory(id: _id, folder: folder);
    } on rust.FerryxError {
      return false;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    onClosed();
    await rust.terminalClose(id: _id);
  }
}
