import 'package:flutter/widgets.dart' show StringCharacters;

/// Reading paths as text, with either separator: what the dialogs show
/// and take (`sub/name`, `C:\Users`), not what the core resolves.
abstract final class PathText {
  static final _separator = RegExp(r'[/\\]');

  /// The index of the last separator, or -1.
  static int lastSeparator(String path) => path.lastIndexOf(_separator);

  /// The last component: the file's or folder's name, the path itself
  /// without a separator, the root for `/`.
  static String baseName(String path) {
    var end = path.length;
    while (end > 1 && _separator.hasMatch(path[end - 1])) {
      end--;
    }
    final trimmed = path.substring(0, end);
    if (trimmed.length <= 1) return trimmed;
    final at = lastSeparator(trimmed);
    return at < 0 ? trimmed : trimmed.substring(at + 1);
  }

  /// The folder of [path]: everything before its last separator, the root
  /// itself for a component at the root, `null` without a separator.
  static String? parentOf(String path) {
    final at = lastSeparator(path);
    if (at < 0) return null;
    return at == 0 ? path.substring(0, 1) : path.substring(0, at);
  }

  /// Whether [path] names a folder from the root: `/a`, `~`, `C:\a`,
  /// `\\server\share`, a server's address (`sftp://me@host/srv`).
  static bool isAbsolute(String path) =>
      path.startsWith('/') ||
      path.startsWith('~') ||
      path.startsWith(r'\\') ||
      path.contains('://') ||
      RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);

  /// [name] under [folder], with the folder's own separator.
  static String join(String folder, String name) {
    if (folder.isEmpty) return name;
    final separator = folder.contains(r'\') && !folder.contains('/')
        ? r'\'
        : '/';
    final base = folder.endsWith('/') || folder.endsWith(r'\')
        ? folder
        : '$folder$separator';
    return '$base$name';
  }

  /// [path] with `~` for the [home] folder it is in or under.
  static String tilde(String path, {required String home}) {
    if (home.length <= 1) return path;
    if (path == home) return '~';
    return path.startsWith('$home/') ? '~${path.substring(home.length)}' : path;
  }

  /// [path] shortened in the middle for a menu's label when it is longer
  /// than [maxLength]: its root, an ellipsis and its last two components.
  static String shortened(String path, {int maxLength = 48}) {
    if (path.characters.length <= maxLength) return path;
    final parts = path.split(_separator).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 3) return path;
    final separator = path.contains(r'\') && !path.contains('/') ? r'\' : '/';
    final root = path.startsWith(separator)
        ? separator
        : '${parts.first}$separator';
    final tail = parts.sublist(parts.length - 2).join(separator);
    return '$root…$separator$tail';
  }
}
