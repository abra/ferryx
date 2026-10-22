import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:terminal_service/terminal_service.dart';
import 'package:xterm/xterm.dart';

import 'folder_sync.dart';

enum TerminalStatus {
  /// No shell yet: it starts when the terminal is first shown.
  stopped,
  starting,
  running,

  /// The shell ended ([TerminalSessionState.exitCode]); Return starts
  /// another.
  exited,

  /// The shell could not start ([TerminalSessionState.error]).
  failed,
}

class TerminalSessionState extends Equatable {
  const TerminalSessionState({
    this.status = TerminalStatus.stopped,
    this.folder,
    this.atPrompt,
    this.title = '',
    this.exitCode,
    this.error,
    this.generation = 0,
  });

  final TerminalStatus status;

  /// The shell's folder, as last reported.
  final String? folder;

  /// The shell waits at its prompt (`false` while a program runs, `null`
  /// where the system cannot tell).
  final bool? atPrompt;

  /// The title a program set (`ESC ] 0 ;`), empty when none did.
  final String title;
  final int? exitCode;
  final FerryxException? error;

  /// Bumped when the emulator is replaced, so the view binds the new one.
  final int generation;

  bool get ended =>
      status == TerminalStatus.exited || status == TerminalStatus.failed;

  TerminalSessionState copyWith({
    TerminalStatus? status,
    String? folder,
    bool? atPrompt,
    bool clearAtPrompt = false,
    String? title,
    int? exitCode,
    bool clearExit = false,
    FerryxException? error,
    bool clearError = false,
    int? generation,
  }) => TerminalSessionState(
    status: status ?? this.status,
    folder: folder ?? this.folder,
    atPrompt: clearAtPrompt ? null : (atPrompt ?? this.atPrompt),
    title: title ?? this.title,
    exitCode: clearExit ? null : (exitCode ?? this.exitCode),
    error: clearError ? null : (error ?? this.error),
    generation: generation ?? this.generation,
  );

  @override
  List<Object?> get props => [
    status,
    folder,
    atPrompt,
    title,
    exitCode,
    error,
    generation,
  ];
}

/// The integrated terminal's session: the shell in the core, the emulator
/// it writes into ([terminal], xterm.dart), the selection ([selection]),
/// and the folder kept in step with the active panel ([FolderSync]).
///
/// Lives as long as the window: hiding the terminal keeps the shell and
/// what it printed. The shell starts the first time the terminal is shown,
/// once the view has measured it, in the active panel's folder.
class TerminalSessionCubit extends Cubit<TerminalSessionState> {
  TerminalSessionCubit({
    required this._service,
    required this._preferences,
    required TargetPlatform platform,
    this.locale,
    DateTime Function()? clock,
  }) : _platform = switch (platform) {
         TargetPlatform.macOS => TerminalTargetPlatform.macos,
         TargetPlatform.windows => TerminalTargetPlatform.windows,
         TargetPlatform.linux => TerminalTargetPlatform.linux,
         _ => TerminalTargetPlatform.unknown,
       },
       _sync = FolderSync(clock: clock),
       super(const TerminalSessionState()) {
    _terminal = _newTerminal();
  }

  final TerminalService _service;
  final PreferencesService _preferences;
  final TerminalTargetPlatform _platform;
  final FolderSync _sync;

  /// The system's language and region (`ru_RU`) for the shell's `LANG`.
  final String? locale;

  late Terminal _terminal;
  final selection = TerminalController();
  final _shellFolders = StreamController<String>.broadcast();
  TerminalSession? _session;
  StreamSubscription<TerminalUpdate>? _updates;
  late ByteConversionSink _decoder;
  (int, int)? _size;
  bool _visible = false;
  bool _wantStart = false;
  bool _starting = false;

  /// A command asked for before the shell's first prompt.
  String? _queued;

  /// The shell has reported its state at least once.
  bool _sawState = false;

  /// The emulator the view shows; replaced on a restart that changes the
  /// scrollback ([TerminalSessionState.generation]).
  Terminal get terminal => _terminal;

  /// Folders the shell went to by itself, for the active panel to open.
  Stream<String> get shellFolders => _shellFolders.stream;

  /// Something is typed on the shell's line and not yet entered.
  bool get lineDirty => _sync.lineDirty;

  Terminal _newTerminal() {
    final terminal = Terminal(
      maxLines: _preferences.current.terminal.scrollback,
      platform: _platform,
    );
    terminal
      ..onOutput = _onInput
      ..onResize = _onResize
      ..onTitleChange = (title) {
        if (!isClosed) emit(state.copyWith(title: title));
      };
    _decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(_TerminalWriter(terminal));
    return terminal;
  }

  // ─── The window ───

  /// The terminal is on screen, the active panel in [folder] (`null`
  /// inside an archive): the shell starts if none runs, or follows.
  void show(String? folder) {
    _visible = true;
    _sync.panel = folder;
    if (_session == null && !_starting && !state.ended) {
      _wantStart = true;
      unawaited(_startIfSized());
    } else {
      _followPanel();
    }
  }

  /// The terminal left the screen; the shell runs on, no longer following
  /// the panel until shown again.
  void hide() => _visible = false;

  /// The active panel is in [folder] now (`null` inside an archive).
  void followFolder(String? folder) {
    _sync.panel = folder;
    if (_visible) _followPanel();
  }

  void _followPanel() {
    final session = _session;
    if (session == null) return;
    final folder = _sync.toShell();
    if (folder == null) return;
    _sync.cdTyped(folder);
    unawaited(
      session.changeDirectory(folder).then((typed) {
        if (!typed) _sync.cdDropped(folder);
      }),
    );
  }

  // ─── The session ───

  void _onResize(int cols, int rows, int pixelWidth, int pixelHeight) {
    _size = (cols, rows);
    final session = _session;
    if (session != null) {
      session.resize(cols, rows);
    } else if (_wantStart) {
      unawaited(_startIfSized());
    }
  }

  Future<void> _startIfSized() async {
    final size = _size;
    if (size == null || _starting || _session != null || isClosed) return;
    _starting = true;
    _wantStart = false;
    emit(
      state.copyWith(
        status: TerminalStatus.starting,
        clearExit: true,
        clearError: true,
        clearAtPrompt: true,
        title: '',
      ),
    );
    final settings = _preferences.current.terminal;
    try {
      final session = await _service.start(
        TerminalStart(
          shell: settings.shell.isEmpty ? null : settings.shell,
          folder: _sync.panel ?? state.folder,
          cols: size.$1,
          rows: size.$2,
          locale: locale,
        ),
      );
      if (isClosed) {
        await session.close();
        return;
      }
      _session = session;
      _updates = session.updates.listen(_onUpdate);
      // The view may have been resized while the shell started.
      final (cols, rows) = _size ?? size;
      if ((cols, rows) != size) session.resize(cols, rows);
      emit(state.copyWith(status: TerminalStatus.running));
    } on FerryxException catch (error) {
      if (!isClosed) {
        emit(state.copyWith(status: TerminalStatus.failed, error: error));
      }
    } finally {
      _starting = false;
    }
  }

  void _onUpdate(TerminalUpdate update) {
    if (isClosed) return;
    switch (update) {
      case TerminalOutput(:final bytes):
        if (bytes.length <= slice) {
          _decoder.add(bytes);
          // The next batch after this turn of the event loop, so a frame
          // can come between two: a flood never freezes the window.
          Timer.run(() => _session?.ack());
        } else {
          // Parsed a slice per turn, the events after it held back so
          // they keep their order.
          final updates = _updates?..pause();
          unawaited(_writeInSlices(bytes, updates));
        }
      case TerminalShellState():
        _sawState = true;
        final target = _sync.onShellState(update);
        emit(state.copyWith(atPrompt: update.idle, folder: update.folder));
        if (target != null) _shellFolders.add(target);
        final queued = _queued;
        if (queued != null && update.idle != false) {
          _queued = null;
          runCommand(queued);
        }
      case TerminalExited(:final exitCode):
        _forgetSession();
        emit(
          state.copyWith(
            status: TerminalStatus.exited,
            exitCode: exitCode,
            clearAtPrompt: true,
          ),
        );
    }
  }

  /// The most output parsed in one turn of the event loop: a few
  /// milliseconds even in a debug build, so frames keep coming while a
  /// command floods the terminal.
  static const slice = 16 * 1024;

  Future<void> _writeInSlices(
    Uint8List bytes,
    StreamSubscription<TerminalUpdate>? updates,
  ) async {
    for (var start = 0; start < bytes.length; start += slice) {
      if (isClosed) return;
      final end = math.min(start + slice, bytes.length);
      _decoder.add(Uint8List.sublistView(bytes, start, end));
      await Future<void>.delayed(Duration.zero);
    }
    if (isClosed || !identical(updates, _updates)) return;
    _session?.ack();
    updates?.resume();
  }

  void _onInput(String data) {
    final session = _session;
    if (session == null) return;
    _sync.typed(data);
    session.write(utf8.encode(data));
  }

  /// Lets go of the shell at once; hanging it up finishes in the
  /// background, so a new shell never waits for the old one's end.
  void _forgetSession() {
    final session = _session;
    final updates = _updates;
    _session = null;
    _updates = null;
    if (updates != null) unawaited(updates.cancel());
    if (session != null) unawaited(session.close());
  }

  /// A new shell after the last one ended (or would not start), below what
  /// it printed. A changed scrollback takes a new, empty emulator.
  Future<void> restart() async {
    _forgetSession();
    if (isClosed) return;
    if (_terminal.maxLines != _preferences.current.terminal.scrollback) {
      _decoder.close();
      selection.clearSelection();
      _terminal = _newTerminal();
      _size = null;
      emit(state.copyWith(generation: state.generation + 1));
    } else {
      // Whatever the last program left on: the alternate screen, a hidden
      // cursor, mouse reporting, bracketed paste, application keys.
      _terminal.write(
        '\x1b[0m\x1b[?1049l\x1b[?25h\x1b[?1000l\x1b[?1002l\x1b[?1003l'
        '\x1b[?1006l\x1b[?2004l\x1b[?1l\r\n',
      );
    }
    _sync.reset();
    _sawState = false;
    _wantStart = true;
    await _startIfSized();
  }

  // ─── Commands ───

  /// Types [command] and Return at the shell's prompt; whether it could. A
  /// shell running a program, or holding a half-typed line, is left alone;
  /// one not started yet, or ended, runs it at its first prompt.
  bool runCommand(String command) {
    final line = command.trim();
    if (line.isEmpty) return true;
    final session = _session;
    if (session == null) {
      _queued = line;
      if (state.ended) unawaited(restart());
      return true;
    }
    if (!_sawState) {
      // Started, but not at its first prompt yet.
      _queued = line;
      return true;
    }
    if (state.atPrompt == false || _sync.lineDirty) return false;
    session.write(utf8.encode('$line\r'));
    return true;
  }

  /// The selected text, `null` when nothing is selected.
  String? selectedText() {
    final range = selection.selection;
    if (range == null) return null;
    final text = _terminal.buffer.getText(range);
    return text.isEmpty ? null : text;
  }

  /// Pastes [text] as the shell's line editor expects a paste (bracketed
  /// when it asked for that), at the end of the scrollback.
  void paste(String text) {
    if (text.isEmpty || _session == null) return;
    selection.clearSelection();
    _terminal.paste(text);
  }

  void selectAll() {
    final buffer = _terminal.buffer;
    if (buffer.height == 0) return;
    selection.setSelection(
      buffer.createAnchor(0, 0),
      buffer.createAnchor(_terminal.viewWidth, buffer.height - 1),
    );
  }

  /// Clears the scrollback, as Terminal.app's ⌘K; a shell at its prompt is
  /// asked to redraw it on a clean screen (⌃L), a running program is left
  /// its screen.
  void clear() {
    selection.clearSelection();
    _terminal.mainBuffer.clearScrollback();
    final session = _session;
    if (session != null &&
        state.atPrompt != false &&
        !_terminal.isUsingAltBuffer) {
      session.write(const [0x0c]);
    }
    _terminal.write('');
  }

  @override
  Future<void> close() async {
    _forgetSession();
    _decoder.close();
    selection.dispose();
    await _shellFolders.close();
    return super.close();
  }
}

/// Writes decoded text into the emulator as it comes.
class _TerminalWriter implements Sink<String> {
  _TerminalWriter(this.terminal);

  final Terminal terminal;

  @override
  void add(String data) {
    if (data.isNotEmpty) terminal.write(data);
  }

  @override
  void close() {}
}
