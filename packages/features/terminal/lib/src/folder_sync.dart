import 'package:domain_models/domain_models.dart';

/// Keeps the shell and the active panel in one folder, both ways, as
/// Nimble Commander does, without either chasing the other.
///
/// - Panel to shell ([toShell]): when the panel goes somewhere and the
///   shell waits at its prompt with nothing typed on its line, the
///   terminal types `cd` there. A shell running a program (vim, ssh, top)
///   or holding a half-typed line is left alone, and a folder inside an
///   archive is never sent.
/// - Shell to panel ([onShellState]): when the shell comes back to its
///   prompt in another folder than at its last prompt (a `cd` typed, a
///   script that moved it), the panel opens that folder.
///
/// A `cd` the terminal typed itself is awaited ([cdTyped]): until the
/// shell reports that folder, or [settle] passes, the shell's folders are
/// not sent back, so a panel moving quickly is never pulled back to where
/// it just was.
class FolderSync {
  FolderSync({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const settle = Duration(seconds: 2);

  final DateTime Function() _clock;

  /// The active panel's folder on disk; `null` inside an archive.
  String? panel;

  bool? _idle;
  String? _promptFolder;
  bool _lineDirty = false;
  String? _pending;
  DateTime? _pendingAt;

  /// Something is typed on the shell's line and not yet entered.
  bool get lineDirty => _lineDirty;

  /// The shell's folder when it last waited at its prompt.
  String? get shellFolder => _promptFolder;

  String? get _pendingFolder {
    final at = _pendingAt;
    if (_pending == null || at == null) return null;
    if (_clock().difference(at) >= settle) {
      _pending = null;
      _pendingAt = null;
    }
    return _pending;
  }

  /// The folder to type `cd` to now, if the panel's folder should reach
  /// the shell: it waits at its prompt, nothing typed, somewhere else.
  String? toShell() {
    final folder = panel;
    if (folder == null || _idle != true || _lineDirty) return null;
    // Not seen at a prompt in a known folder yet.
    if (_promptFolder == null) return null;
    if (folder == _promptFolder || folder == _pendingFolder) return null;
    return folder;
  }

  /// The terminal typed `cd` to [folder].
  void cdTyped(String folder) {
    _pending = folder;
    _pendingAt = _clock();
  }

  /// The core did not type it after all (the shell was busy or there
  /// already).
  void cdDropped(String folder) {
    if (_pending == folder) {
      _pending = null;
      _pendingAt = null;
    }
  }

  /// The shell's state changed; answers the folder the panel should open,
  /// if the shell went there by itself.
  String? onShellState(TerminalShellState state) {
    final wasBusy = _idle == false;
    _idle = state.idle;
    final folder = state.folder;
    if (state.idle != true || folder == null) return null;
    // A fresh prompt after a program: its line is empty.
    if (wasBusy) _lineDirty = false;
    final previous = _promptFolder;
    _promptFolder = folder;
    final pending = _pendingFolder;
    if (pending != null) {
      if (folder == pending) cdDropped(pending);
      return null;
    }
    // The first prompt is where the shell was started.
    if (previous == null || folder == previous || folder == panel) {
      return null;
    }
    return folder;
  }

  /// The user typed [data] into the shell: a line ended (Return, ⌃C, ⌃U,
  /// ⌃D) leaves it clean, anything else leaves text on it. Focus reports
  /// are the terminal's, not the user's.
  void typed(String data) {
    if (data.isEmpty || data == '\x1b[I' || data == '\x1b[O') return;
    final last = data.codeUnitAt(data.length - 1);
    _lineDirty = !const {0x0d, 0x03, 0x15, 0x04}.contains(last);
  }

  /// A new shell: nothing is known of it yet.
  void reset() {
    _idle = null;
    _promptFolder = null;
    _lineDirty = false;
    _pending = null;
    _pendingAt = null;
  }
}
