import 'dart:typed_data';

/// What a terminal session starts with.
class TerminalStart {
  const TerminalStart({
    required this.cols,
    required this.rows,
    this.shell,
    this.folder,
    this.locale,
  });

  /// The shell from the settings; the user's own when `null` or empty.
  final String? shell;

  /// The native folder to start in; the home folder when `null` or gone.
  final String? folder;
  final int cols;
  final int rows;

  /// The system's language and region (`ru_RU`), for `LANG` when the
  /// environment names no locale.
  final String? locale;
}

/// What a terminal session reports.
sealed class TerminalUpdate {
  const TerminalUpdate();
}

/// Output of the shell or its programs; acknowledge it once it is parsed,
/// or no more comes.
final class TerminalOutput extends TerminalUpdate {
  const TerminalOutput(this.bytes);

  final Uint8List bytes;
}

/// The shell's state changed.
final class TerminalShellState extends TerminalUpdate {
  const TerminalShellState({this.idle, this.folder});

  /// The shell waits at its prompt rather than running a program; `null`
  /// where the system cannot tell (Windows).
  final bool? idle;

  /// The shell's folder; `null` where the system cannot tell.
  final String? folder;

  @override
  bool operator ==(Object other) =>
      other is TerminalShellState &&
      other.idle == idle &&
      other.folder == folder;

  @override
  int get hashCode => Object.hash(idle, folder);

  @override
  String toString() => 'TerminalShellState(idle: $idle, folder: $folder)';
}

/// The shell ended: its exit code, `null` when a signal ended it.
final class TerminalExited extends TerminalUpdate {
  const TerminalExited(this.exitCode);

  final int? exitCode;
}
